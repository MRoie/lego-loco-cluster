#!/usr/bin/env node
/**
 * debug-webrtc.js - Debug WebRTC connection from Playwright.
 * Polls video element state every second for 25s to see if connection succeeds.
 */
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({
    headless: true,
    args: [
      '--autoplay-policy=no-user-gesture-required',
      '--use-fake-ui-for-media-stream',
      '--disable-web-security',
      '--disable-gpu',
      '--no-sandbox',
    ],
  });
  const context = await browser.newContext({ viewport: { width: 1280, height: 960 } });
  const page = await context.newPage();

  const logs = [];
  page.on('console', (msg) => logs.push({ type: msg.type(), text: msg.text() }));
  page.on('pageerror', (err) => logs.push({ type: 'error', text: err.message }));
  page.on('crash', () => { console.log('PAGE CRASHED!'); logs.push({ type: 'crash', text: 'Page crashed' }); });

  console.log('Loading dashboard...');
  await page.goto('http://localhost:3000', { waitUntil: 'networkidle', timeout: 30000 });
  console.log('Page loaded, injecting SDP logger...');
  
  // Inject SDP and track monitoring
  await page.evaluate(() => {
    const origSetRemote = RTCPeerConnection.prototype.setRemoteDescription;
    RTCPeerConnection.prototype.setRemoteDescription = function(desc) {
      console.log('SDP_ANSWER:' + desc.sdp);
      return origSetRemote.call(this, desc);
    };
    // Monitor ontrack
    const origOntrackSetter = Object.getOwnPropertyDescriptor(RTCPeerConnection.prototype, 'ontrack').set;
    Object.defineProperty(RTCPeerConnection.prototype, 'ontrack', {
      set: function(fn) {
        origOntrackSetter.call(this, function(ev) {
          const trackInfo = { kind: ev.track.kind, id: ev.track.id, readyState: ev.track.readyState };
          const streamInfo = ev.streams.map(s => ({ id: s.id, audioTracks: s.getAudioTracks().length, videoTracks: s.getVideoTracks().length }));
          console.log('ONTRACK_FIRED:' + JSON.stringify({ track: trackInfo, streams: streamInfo, transceiver: ev.transceiver ? ev.transceiver.direction : 'none' }));
          return fn.call(this, ev);
        });
      },
      get: Object.getOwnPropertyDescriptor(RTCPeerConnection.prototype, 'ontrack').get,
      configurable: true,
    });
  });
  console.log('Polling video state for 25s...');

  for (let i = 0; i < 25; i++) {
    try { await page.waitForTimeout(1000); } catch (e) { console.log('Page died at t=' + (i+1) + 's:', e.message); break; }
    let vs;
    try { vs = await page.evaluate(() => {
      const videos = document.querySelectorAll('video');
      return Array.from(videos).map((v) => ({
        so: v.srcObject != null,
        rs: v.readyState,
        w: v.videoWidth,
        h: v.videoHeight,
        at: v.srcObject ? v.srcObject.getAudioTracks().length : 0,
        vt: v.srcObject ? v.srcObject.getVideoTracks().length : 0,
      }));
    });
    } catch (e) { console.log('Evaluate died at t=' + (i+1) + 's:', e.message); break; }
    if (vs.length > 0) {
      const connected = vs.filter(v => v.so);
      if (connected.length > 0) {
        console.log('  t=' + (i + 1) + 's: ' + connected.length + ' connected', JSON.stringify(connected));
      } else if (i % 5 === 4) {
        console.log('  t=' + (i + 1) + 's: ' + vs.length + ' video elements, none connected');
      }
    } else if (i % 5 === 4) {
      console.log('  t=' + (i + 1) + 's: no video elements');
    }
  }

  // Final state
  let final;
  try {
    final = await page.evaluate(() => {
    const videos = document.querySelectorAll('video');
    return Array.from(videos).map((v) => ({
      hasSrcObject: v.srcObject != null,
      readyState: v.readyState,
      videoWidth: v.videoWidth,
      videoHeight: v.videoHeight,
      paused: v.paused,
      muted: v.muted,
      audioTracks: v.srcObject
        ? v.srcObject.getAudioTracks().map((t) => ({
            label: t.label, enabled: t.enabled, readyState: t.readyState
          }))
        : [],
      videoTracks: v.srcObject
        ? v.srcObject.getVideoTracks().map((t) => ({
            label: t.label, enabled: t.enabled, readyState: t.readyState
          }))
        : [],
    }));
  });
  } catch (e) { console.log('Final evaluate failed:', e.message); final = null; }
  if (final) console.log('\nFinal:', JSON.stringify(final, null, 2));

  // Relevant logs
  const sdpLogs = logs.filter((l) => l.text.startsWith('SDP_ANSWER:'));
  if (sdpLogs.length > 0) {
    console.log('\nSDP Answer received:');
    const sdp = sdpLogs[0].text.replace('SDP_ANSWER:', '');
    // Show m-lines and codec lines
    sdp.split('\r\n').filter(line => /^(m=|a=rtpmap|a=fmtp|a=sendonly|a=recvonly|a=sendrecv|a=inactive)/.test(line))
      .forEach(line => console.log('  ' + line));
  }

  const relevant = logs.filter((l) =>
    /webrtc|signal|rtc|ice|sdp|offer|answer|track|error|warn|fail|ws|websocket|peer|connect/i.test(l.text)
  );
  console.log('\nRelevant logs (' + relevant.length + ' of ' + logs.length + '):');
  relevant.slice(-20).forEach((l) =>
    console.log('  [' + l.type + '] ' + l.text.substring(0, 250))
  );

  await browser.close();
  console.log('\nDone.');
})();
