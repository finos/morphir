import { defineConfig } from 'vite'
//import elmPlugin from 'vite-plugin-elm'
import elm from 'vite-plugin-elm-watch'


export default defineConfig(({ command, mode, isSsrBuild, isPreview }) => {
    if (command === 'serve') {
        return {
            plugins: [elm({ mode: 'debug' })]
        }
    } else {
        return {
            plugins: [elm()]
        }
    }
})