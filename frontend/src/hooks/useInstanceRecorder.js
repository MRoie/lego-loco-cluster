import { useRef, useCallback, useState } from 'react';
import { recorderMimeForFormat, downloadFilename, downloadBlob } from '../utils/mediaExport';

/**
 * Records a single instance's WebRTC stream (video + audio) to a downloadable file.
 *
 * Usage:
 *   const { recording, startRecording, stopRecording } = useInstanceRecorder(videoRef, 'webm');
 *   startRecording();   // captures from the <video> element's srcObject
 *   stopRecording();    // triggers a browser download
 *
 * @param {React.RefObject} videoRef - ref to the <video> element with srcObject
 * @param {string} format - export format key (webm, mp4, mkv, mp3)
 * @param {string} [instanceId] - used in the download filename
 */
export default function useInstanceRecorder(videoRef, format = 'webm', instanceId = 'instance') {
  const recorderRef = useRef(null);
  const chunksRef = useRef([]);
  const [recording, setRecording] = useState(false);

  const startRecording = useCallback(() => {
    const vid = videoRef?.current;
    if (!vid || !vid.srcObject) {
      console.warn('useInstanceRecorder: no srcObject on video element');
      return;
    }

    const stream = vid.srcObject;
    const mimeType = recorderMimeForFormat(format);
    chunksRef.current = [];

    try {
      const recorder = new MediaRecorder(stream, { mimeType });

      recorder.ondataavailable = (e) => {
        if (e.data && e.data.size > 0) {
          chunksRef.current.push(e.data);
        }
      };

      recorder.onstop = () => {
        const blob = new Blob(chunksRef.current, { type: mimeType });
        const filename = `${instanceId}-${downloadFilename(format)}`;
        downloadBlob(blob, filename);
        chunksRef.current = [];
      };

      recorder.start(1000);
      recorderRef.current = recorder;
      setRecording(true);
    } catch (err) {
      console.error('useInstanceRecorder: failed to start', err);
    }
  }, [videoRef, format, instanceId]);

  const stopRecording = useCallback(() => {
    if (recorderRef.current && recorderRef.current.state !== 'inactive') {
      recorderRef.current.stop();
      recorderRef.current = null;
    }
    setRecording(false);
  }, []);

  return { recording, startRecording, stopRecording };
}
