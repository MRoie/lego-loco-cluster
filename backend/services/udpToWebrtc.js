const dgram = require('dgram');
const { RTCPeerConnection, RTCRtpCodecParameters, MediaStreamTrack, useNACK, usePLI, useREMB } = require('werift');
const logger = require('../utils/logger');

class UdpToWebRTC {
    constructor() {
        this.videoSocket = dgram.createSocket('udp4');
        this.audioSocket = dgram.createSocket('udp4');
        this.peers = new Map(); // id -> RTCPeerConnection
        this.tracks = []; // Array of MediaStreamTrack

        // Create a video track for H264
        this.videoTrack = new MediaStreamTrack({ kind: 'video' });

        // Create an audio track for Opus
        this.audioTrack = new MediaStreamTrack({ kind: 'audio' });

        this.setupUdp();
    }

    setupUdp() {
        let videoCount = 0;
        let audioCount = 0;
        // Log packet counts every 5 seconds
        setInterval(() => {
            if (videoCount > 0 || audioCount > 0) {
                logger.info(`RTP packets received - video: ${videoCount}, audio: ${audioCount}`);
            }
        }, 5000);

        // Video UDP listener (port 5000)
        this.videoSocket.on('error', (err) => {
            logger.error(`Video UDP server error:\n${err.stack}`);
            this.videoSocket.close();
        });

        this.videoSocket.on('message', (msg, rinfo) => {
            videoCount++;
            try {
                this.videoTrack.writeRtp(msg);
            } catch (e) {
                // Suppress errors for malformed packets
                if (videoCount < 5) logger.warn(`Video writeRtp error: ${e.message}`);
            }
        });

        this.videoSocket.bind(5000);
        logger.info("UDP Video Bridge listening on 5000 (WERIFT - VP8)");

        // Audio UDP listener (port 5001)
        this.audioSocket.on('error', (err) => {
            logger.error(`Audio UDP server error:\n${err.stack}`);
            this.audioSocket.close();
        });

        this.audioSocket.on('message', (msg, rinfo) => {
            audioCount++;
            try {
                this.audioTrack.writeRtp(msg);
            } catch (e) {
                // Suppress errors for malformed packets
                if (audioCount < 5) logger.warn(`Audio writeRtp error: ${e.message}`);
            }
        });

        this.audioSocket.bind(5001);
        logger.info("UDP Audio Bridge listening on 5001 (WERIFT - Opus)");
    }

    createConnection(iceServers = []) {
        // Announce IP for ICE candidates (use node/host IP when behind NAT/K8s)
        const announceIp = process.env.WEBRTC_ANNOUNCE_IP;
        // Port range for WebRTC UDP (useful when exposing via NodePort/hostPort)
        const portRange = process.env.WEBRTC_PORT_RANGE
            ? process.env.WEBRTC_PORT_RANGE.split('-').map(Number)
            : undefined;

        const pc = new RTCPeerConnection({
            iceServers,
            iceAdditionalHostAddresses: announceIp ? [announceIp] : undefined,
            icePortRange: portRange,
            codecs: {
                audio: [
                    new RTCRtpCodecParameters({
                        mimeType: "audio/opus",
                        clockRate: 48000,
                        channels: 2,
                    }),
                ],
                video: [
                    // VP8 - universally supported (including headless Chromium)
                    // GStreamer pipeline must use vp8enc + rtpvp8pay to match
                    new RTCRtpCodecParameters({
                        mimeType: "video/VP8",
                        clockRate: 90000,
                        rtcpFeedback: [useNACK(), usePLI(), useREMB()],
                    }),
                ],
            },
        });

        // Add the video track (sendonly)
        const videoTransceiver = pc.addTransceiver(this.videoTrack, {
            direction: 'sendonly',
        });

        // Add the audio track (sendonly)
        const audioTransceiver = pc.addTransceiver(this.audioTrack, {
            direction: 'sendonly',
        });

        // Helper to log connection state
        pc.connectionStateChange.subscribe((state) => {
            logger.info(`PeerConnection State: ${state}`);
            if (state === 'failed' || state === 'closed') {
                pc.close();
            }
        });

        return pc;
    }
}

module.exports = new UdpToWebRTC();
