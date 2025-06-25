import { useEffect, useRef, useState } from "react";

/**
 * Establish a WebRTC connection for the given target instance ID.
 * Returns a video ref and current audio level for UI binding.
 */
export default function useWebRTC(targetId) {
  // <video> element that will display the incoming stream
  const videoRef = useRef(null);
  // simple numeric audio meter 0-1 updated from Web Audio API
  const [audioLevel, setAudioLevel] = useState(0);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!targetId) return;
    let cancelled = false;
    let reconnectTimer = null;

    const scheduleReconnect = () => {
      if (cancelled || reconnectTimer) return;
      setLoading(true);
      reconnectTimer = setTimeout(() => {
        reconnectTimer = null;
        connect();
      }, 1000);
    };

    async function connect() {
      setLoading(true);
      // Fetch optional ICE server configuration. In a Kubernetes cluster we
      // typically don't need external STUN/TURN servers, so this defaults to an
      // empty array when the config isn't present.
      const iceServers = await fetch("/api/config/webrtc")
        .then((r) => r.json())
        .then((cfg) => cfg.iceServers || [])
        .catch((e) => {
          console.error("Failed to load WebRTC config", e);
          return [];
        });

      if (cancelled) return;

      const wsProto = location.protocol === "https:" ? "wss" : "ws";
      const ws = new WebSocket(`${wsProto}://${location.host}/signal`);
      const pc = new RTCPeerConnection({ iceServers });

        let audioCtx;
        let analyser;

        const dataArr = new Uint8Array(128);

        function startMeter(stream) {
          audioCtx = new (window.AudioContext || window.webkitAudioContext)();
          const source = audioCtx.createMediaStreamSource(stream);
          analyser = audioCtx.createAnalyser();
          analyser.fftSize = 256;
          source.connect(analyser);
          const tick = () => {
            if (!analyser) return;
            analyser.getByteFrequencyData(dataArr);
            const sum = dataArr.reduce((s, v) => s + v, 0);
            setAudioLevel(sum / dataArr.length / 255);
            requestAnimationFrame(tick);
          };
          tick();
        }

        pc.ontrack = (ev) => {
          const [stream] = ev.streams;
          if (videoRef.current) {
            videoRef.current.srcObject = stream;
            videoRef.current
              .play()
              .catch((e) => console.error("video play failed", e));
          }
          if (!audioCtx) startMeter(stream);
          setLoading(false);
        };

        pc.onicecandidate = ({ candidate }) => {
          if (candidate) {
            ws.send(
              JSON.stringify({
                type: "signal",
                target: targetId,
                data: candidate,
              }),
            );
          }
        };

        ws.onopen = async () => {
          ws.send(JSON.stringify({ type: "register" }));
          const offer = await pc.createOffer();
          await pc.setLocalDescription(offer);
          ws.send(
            JSON.stringify({
              type: "signal",
              target: targetId,
              data: pc.localDescription,
            }),
          );
        };

        ws.onerror = (e) => {
          console.error("WebSocket error", e);
        };

        ws.onclose = () => {
          console.log("WebSocket closed for", targetId);
          scheduleReconnect();
        };

        pc.onconnectionstatechange = () => {
          if (pc.connectionState === 'failed' || pc.connectionState === 'disconnected') {
            console.log('Peer connection lost, reconnecting');
            ws.close();
            pc.close();
            scheduleReconnect();
          }
        };

        ws.onmessage = async (ev) => {
          const msg = JSON.parse(ev.data);
          if (msg.type === "signal" && msg.data) {
            if (msg.data.sdp) {
              await pc.setRemoteDescription(
                new RTCSessionDescription(msg.data),
              );
              if (msg.data.type === "offer") {
                const ans = await pc.createAnswer();
                await pc.setLocalDescription(ans);
                ws.send(
                  JSON.stringify({
                    type: "signal",
                    target: msg.from || targetId,
                    data: pc.localDescription,
                  }),
                );
              }
            } else if (msg.data.candidate) {
              try {
                await pc.addIceCandidate(new RTCIceCandidate(msg.data));
              } catch (e) {
                console.warn("Failed to add ICE candidate", e);
              }
            }
          }
        };

        return () => {
          ws.close();
          pc.close();
          if (audioCtx) audioCtx.close();
        };
      }

    connect();

    return () => {
      cancelled = true;
      if (reconnectTimer) {
        clearTimeout(reconnectTimer);
        reconnectTimer = null;
      }
      if (videoRef.current) videoRef.current.srcObject = null;
    };
  }, [targetId]);

  return { videoRef, audioLevel, loading };
}
