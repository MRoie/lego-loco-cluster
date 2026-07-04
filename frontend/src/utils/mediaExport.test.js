import { describe, it, expect } from 'vitest';
import {
  EXPORT_FORMATS,
  FORMAT_KEYS,
  recorderMimeForFormat,
  downloadFilename,
} from './mediaExport';

describe('EXPORT_FORMATS', () => {
  it('contains all expected format keys', () => {
    expect(FORMAT_KEYS).toEqual(expect.arrayContaining(['webm', 'mp4', 'mkv', 'gif', 'mp3']));
  });

  it('each format has label, ext, mime, and type', () => {
    for (const key of FORMAT_KEYS) {
      const fmt = EXPORT_FORMATS[key];
      expect(fmt).toHaveProperty('label');
      expect(fmt).toHaveProperty('ext');
      expect(fmt).toHaveProperty('mime');
      expect(fmt).toHaveProperty('type');
      expect(['video', 'audio']).toContain(fmt.type);
    }
  });

  it('mp3 is audio type, others are video', () => {
    expect(EXPORT_FORMATS.mp3.type).toBe('audio');
    expect(EXPORT_FORMATS.webm.type).toBe('video');
    expect(EXPORT_FORMATS.mp4.type).toBe('video');
    expect(EXPORT_FORMATS.mkv.type).toBe('video');
    expect(EXPORT_FORMATS.gif.type).toBe('video');
  });
});

describe('recorderMimeForFormat', () => {
  it('returns a webm MIME for webm format', () => {
    const mime = recorderMimeForFormat('webm');
    expect(mime).toContain('video/webm');
  });

  it('returns a MIME string for mp4 format', () => {
    const mime = recorderMimeForFormat('mp4');
    expect(mime).toBeTruthy();
    expect(typeof mime).toBe('string');
  });

  it('returns a webm MIME for mkv format', () => {
    const mime = recorderMimeForFormat('mkv');
    expect(mime).toContain('video/webm');
  });

  it('returns an audio MIME for mp3 format', () => {
    const mime = recorderMimeForFormat('mp3');
    expect(mime).toContain('audio/');
  });

  it('returns a webm MIME for gif format', () => {
    const mime = recorderMimeForFormat('gif');
    expect(mime).toContain('video/webm');
  });
});

describe('downloadFilename', () => {
  it('generates filenames with correct extensions', () => {
    expect(downloadFilename('webm')).toMatch(/\.webm$/);
    expect(downloadFilename('mp4')).toMatch(/\.mp4$/);
    expect(downloadFilename('mkv')).toMatch(/\.mkv$/);
    expect(downloadFilename('gif')).toMatch(/\.gif$/);
    expect(downloadFilename('mp3')).toMatch(/\.mp3$/);
  });

  it('includes a timestamp in the filename', () => {
    const name = downloadFilename('webm');
    expect(name).toMatch(/vr-spatial-audio-\d+\.webm/);
  });

  it('falls back to webm for unknown format', () => {
    const name = downloadFilename('unknown');
    expect(name).toMatch(/\.webm$/);
  });
});
