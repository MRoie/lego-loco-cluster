import { useRef, useCallback, useState } from 'react';
import {
  recorderMimeForFormat,
  downloadFilename,
  downloadBlob,
  createGifRecorder,
  EXPORT_FORMATS,
} from '../utils/mediaExport';

/**
 * Records the A-Frame <canvas> in multiple formats.
 *
 * Supported formats: webm, mp4, mkv, gif, mp3
 *
 * Usage:
 *   const { videoRecording, startVideoRecording, stopVideoRecording } = useVideoRecorder('webm');
 *   startVideoRecording();   // captures the <a-scene> canvas
 *   stopVideoRecording();    // triggers a browser download in the chosen format
 */
export default function useVideoRecorder(format = 'webm', fps = 30) {
  const recorderRef = useRef(null);
  const chunksRef = useRef([]);
  const gifRef = useRef(null);
  const [videoRecording, setVideoRecording] = useState(false);

  const startVideoRecording = useCallback(() => {
    const scene = document.querySelector('a-scene');
    if (!scene) return;
    const canvas = scene.canvas;
    if (!canvas) return;

    chunksRef.current = [];

    // GIF uses a separate frame-capture pipeline
    if (format === 'gif') {
      const gif = createGifRecorder(canvas, 10);
      gif.start();
      gifRef.current = gif;
      setVideoRecording(true);
      return;
    }

    const isAudioOnly = EXPORT_FORMATS[format]?.type === 'audio';
    const mimeType = recorderMimeForFormat(format);

    let stream;
    if (isAudioOnly) {
      // Capture audio from the AudioContext destination via the canvas stream
      // (canvas stream includes audio tracks when A-Frame scenes have audio)
      stream = canvas.captureStream(0); // 0 fps = no video frames
      // If no audio tracks, fall back to full capture
      if (stream.getAudioTracks().length === 0) {
        stream = canvas.captureStream(fps);
      }
    } else {
      stream = canvas.captureStream(fps);
    }

    const recorder = new MediaRecorder(stream, { mimeType });

    recorder.ondataavailable = (e) => {
      if (e.data && e.data.size > 0) {
        chunksRef.current.push(e.data);
      }
    };

    recorder.onstop = () => {
      const blob = new Blob(chunksRef.current, { type: mimeType });
      downloadBlob(blob, downloadFilename(format));
      chunksRef.current = [];
    };

    recorder.start(1000);
    recorderRef.current = recorder;
    setVideoRecording(true);
  }, [format, fps]);

  const stopVideoRecording = useCallback(() => {
    // GIF path
    if (gifRef.current) {
      gifRef.current.stop();
      const blob = gifRef.current.getBlob();
      downloadBlob(blob, downloadFilename('gif'));
      gifRef.current = null;
      setVideoRecording(false);
      return;
    }

    // MediaRecorder path (webm, mp4, mkv, mp3)
    if (recorderRef.current && recorderRef.current.state !== 'inactive') {
      recorderRef.current.stop();
      recorderRef.current = null;
    }
    setVideoRecording(false);
  }, []);

  return { videoRecording, startVideoRecording, stopVideoRecording };
}
