const dgram = require('dgram');
const { RTCPeerConnection, RTCRtpCodecParameters, MediaStreamTrack } = require('werift');
const logger = require('../utils/logger');

class UdpToWebRTC {
    constructor() {
        this.udpSocket = dgram.createSocket('udp4');
        this.peers = new Map(); // id -> RTCPeerConnection
        this.tracks = []; // Array of MediaStreamTrack

        // Create a video track for H264
        this.videoTrack = new MediaStreamTrack({ kind: 'video' });

        this.setupUdp();
    }

    setupUdp() {
        this.udpSocket.on('error', (err) => {
            logger.error(`UDP server error:\n${err.stack}`);
            this.udpSocket.close();
        });

        this.udpSocket.on('message', (msg, rinfo) => {
            // Incoming RTP packet from Emulator (GStreamer)
            // Werift expects RtpPacket object or Buffer?
            // MediaStreamTrack.writeRtp(buffer)
            try {
                this.videoTrack.writeRtp(msg);
            } catch (e) {
                // Suppress errors for malformed packets to avoid log spam
            }
        });

        this.udpSocket.bind(5000);
        logger.info("UDP Bridge listening on 5000 (WERIFT)");
    }

    async createConnection(iceServers = []) {
        const pc = new RTCPeerConnection({ iceServers });

        // Add the video track
        // Transceiver init for H264
        const transceiver = pc.addTransceiver(this.videoTrack, {
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
