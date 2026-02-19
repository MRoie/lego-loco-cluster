import { useRef, useCallback, useState } from 'react';

/**
 * Records the A-Frame <canvas> as a WebM video using MediaRecorder.
 *
 * Usage:
 *   const { videoRecording, startVideoRecording, stopVideoRecording } = useVideoRecorder();
 *   // Start: captures the <a-scene> canvas at the given FPS
 *   startVideoRecording();
 *   // Stop: triggers a browser download of the .webm file
 *   stopVideoRecording();
 */
export default function useVideoRecorder(fps = 30) {
  const recorderRef = useRef(null);
  const chunksRef = useRef([]);
  const [videoRecording, setVideoRecording] = useState(false);

  const startVideoRecording = useCallback(() => {
    const scene = document.querySelector('a-scene');
    if (!scene) return;
    const canvas = scene.canvas;
    if (!canvas) return;

    chunksRef.current = [];

    const stream = canvas.captureStream(fps);
    const mimeType = MediaRecorder.isTypeSupported('video/webm;codecs=vp9')
      ? 'video/webm;codecs=vp9'
      : 'video/webm';
    const recorder = new MediaRecorder(stream, { mimeType });

    recorder.ondataavailable = (e) => {
      if (e.data && e.data.size > 0) {
        chunksRef.current.push(e.data);
      }
    };

    recorder.onstop = () => {
      const blob = new Blob(chunksRef.current, { type: mimeType });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `vr-spatial-audio-${Date.now()}.webm`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      chunksRef.current = [];
    };

    recorder.start(1000); // collect data every second
    recorderRef.current = recorder;
    setVideoRecording(true);
  }, [fps]);

  const stopVideoRecording = useCallback(() => {
    if (recorderRef.current && recorderRef.current.state !== 'inactive') {
      recorderRef.current.stop();
      recorderRef.current = null;
    }
    setVideoRecording(false);
  }, []);

  return { videoRecording, startVideoRecording, stopVideoRecording };
}
