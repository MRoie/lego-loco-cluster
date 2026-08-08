import React, { useState, useEffect } from 'react';

/**
 * The VNC controls cheat-sheet, as one header button + modal.
 *
 * This text used to be painted onto every instance tile. It is identical for
 * all of them, and at tile size it covered most of the picture and absorbed
 * clicks that were meant for the guest — you could not use the machine you
 * were reading the instructions for.
 */
const RELEASE_KEYS = [
  ['Ctrl + Alt + R', 'primary'],
  ['Ctrl + Shift + Esc', ''],
  ['F10 ×3', 'VR-friendly'],
  ['Ctrl + Alt + Q', ''],
];

export default function ControlsHelpModal() {
  const [open, setOpen] = useState(false);

  useEffect(() => {
    if (!open) return undefined;
    const onKey = (e) => e.key === 'Escape' && setOpen(false);
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open]);

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        className="bg-black/60 text-green-400 text-xs font-mono px-2 py-1 rounded border border-green-500/30 hover:bg-black/80"
        title="Keyboard and mouse controls"
        aria-label="Keyboard and mouse controls"
      >
        ⓘ CONTROLS
      </button>

      {open && (
        <div
          className="fixed inset-0 z-[200] flex items-center justify-center bg-black/70 p-4"
          onClick={() => setOpen(false)}
        >
          <div
            className="max-w-md w-full rounded-lg border border-green-500/40 bg-neutral-900 p-5 text-sm text-white shadow-xl"
            onClick={(e) => e.stopPropagation()}
            role="dialog"
            aria-modal="true"
            aria-label="Controls"
          >
            <div className="mb-3 flex items-center justify-between">
              <h2 className="font-mono text-base font-bold text-green-400">Controls</h2>
              <button
                onClick={() => setOpen(false)}
                className="rounded px-2 text-lg leading-none text-neutral-400 hover:text-white"
                aria-label="Close"
              >
                ×
              </button>
            </div>

            <p className="mb-3 text-neutral-300">
              Click a tile to take control. Mouse and keyboard go straight to the
              machine — including right-click menus, function keys and modifiers.
            </p>

            <div className="mb-1 font-semibold text-yellow-400">Release control</div>
            <ul className="mb-3 space-y-1">
              {RELEASE_KEYS.map(([combo, note]) => (
                <li key={combo} className="flex items-baseline gap-2">
                  <kbd className="rounded bg-neutral-800 px-1.5 py-0.5 font-mono text-xs">{combo}</kbd>
                  {note && <span className="text-xs text-neutral-400">{note}</span>}
                </li>
              ))}
            </ul>

            <p className="text-xs text-neutral-400">
              The guest cursor tracks yours directly. If it ever drifts, move to a
              screen corner — that re-synchronises it exactly.
            </p>
          </div>
        </div>
      )}
    </>
  );
}
