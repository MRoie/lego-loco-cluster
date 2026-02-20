const dgram = require('dgram');
const { RTCPeerConnection, RTCRtpCodecParameters, MediaStreamTrack } = require('werift');
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
        // Video UDP listener (port 5000)
        this.videoSocket.on('error', (err) => {
            logger.error(`Video UDP server error:\n${err.stack}`);
            this.videoSocket.close();
        });

        this.videoSocket.on('message', (msg, rinfo) => {
            try {
                this.videoTrack.writeRtp(msg);
            } catch (e) {
                // Suppress errors for malformed packets
            }
        });

        this.videoSocket.bind(5000);
        logger.info("UDP Video Bridge listening on 5000 (WERIFT)");

        // Audio UDP listener (port 5001)
        this.audioSocket.on('error', (err) => {
            logger.error(`Audio UDP server error:\n${err.stack}`);
            this.audioSocket.close();
        });

        this.audioSocket.on('message', (msg, rinfo) => {
            try {
                this.audioTrack.writeRtp(msg);
            } catch (e) {
                // Suppress errors for malformed packets
            }
        });

        this.audioSocket.bind(5001);
        logger.info("UDP Audio Bridge listening on 5001 (WERIFT - Opus)");
    }

    async createConnection(iceServers = []) {
        const pc = new RTCPeerConnection({ iceServers });

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
