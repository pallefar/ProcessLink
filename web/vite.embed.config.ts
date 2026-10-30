import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  base: './',
  define: { 'process.env.NODE_ENV': JSON.stringify('production') },
  build: {
    outDir: 'dist',
    emptyOutDir: false,
    lib: {
      entry: 'src/embed.tsx',
      formats: ['es'],
      fileName: () => 'embed.js',
    },
    rollupOptions: { output: { inlineDynamicImports: true } },
  },
})
