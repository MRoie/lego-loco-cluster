import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 3000,
    host: true, // Listen on all addresses
  },
  build: {
    outDir: 'dist',
    target: 'esnext',
    rollupOptions: {
      output: {
        format: 'es'
      }
    }
  },
  esbuild: {
    target: 'esnext'
  },
  optimizeDeps: {
    include: ['react-vnc'],
    esbuildOptions: {
      target: 'esnext'
    }
  },
  define: {
    global: 'globalThis'
  }
});
