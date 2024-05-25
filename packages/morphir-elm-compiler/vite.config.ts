
import { defineConfig } from 'vite'
//import elmPlugin from 'vite-plugin-elm'
import elm from 'vite-plugin-elm-watch'

export default defineConfig(({ command, mode, isSsrBuild, isPreview }) => {
    let isServe = command === 'serve'
    return {        
        plugins: [elm({ mode: 'debug' })]
    };
})