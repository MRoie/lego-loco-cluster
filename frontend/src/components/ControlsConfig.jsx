import React, { useState } from 'react';

export default function ControlsConfig({ controllerMap, keyboardMap, onSave, showToast }) {
  const [open, setOpen] = useState(false);
  const [controllerText, setControllerText] = useState(
    JSON.stringify(controllerMap, null, 2)
  );
  const [keyboardText, setKeyboardText] = useState(
    JSON.stringify(keyboardMap, null, 2)
  );
  const [errorMessage, setErrorMessage] = useState('');

  const handleSave = () => {
    try {
      const newController = JSON.parse(controllerText);
      const newKeyboard = JSON.parse(keyboardText);
      onSave(newController, newKeyboard);
      setErrorMessage('');
      setOpen(false);
    } catch (e) {
      const msg = 'Invalid JSON. Please check your input.';
      setErrorMessage(msg);
      if (showToast) showToast(msg);
    }
  };

  return (
    <div className="relative inline-block text-left">
      <button
        className="bg-gray-700 text-white px-2 py-1 rounded text-xs"
        onClick={() => setOpen(!open)}
      >
        Controls
      </button>
      {open && (
        <div className="absolute right-0 mt-2 w-64 bg-gray-800 text-white p-2 rounded shadow-lg z-50">
          <label className="block text-xs mb-1">Controller Map</label>
          <textarea
            className="w-full text-black text-xs p-1 h-24"
            value={controllerText}
            onChange={e => setControllerText(e.target.value)}
          />
          <label className="block text-xs mt-2 mb-1">Keyboard Map</label>
          <textarea
            className="w-full text-black text-xs p-1 h-24"
            value={keyboardText}
            onChange={e => setKeyboardText(e.target.value)}
          />
          {errorMessage && (
            <div className="text-red-400 text-xs mt-1">{errorMessage}</div>
          )}
          <div className="mt-2 flex justify-end space-x-2">
            <button
              className="bg-blue-500 px-2 py-1 rounded text-xs"
              onClick={handleSave}
            >
              Save
            </button>
            <button
              className="bg-gray-600 px-2 py-1 rounded text-xs"
              onClick={() => setOpen(false)}
            >
              Cancel
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
