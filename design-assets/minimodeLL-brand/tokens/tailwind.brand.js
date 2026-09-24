// Merge into tailwind.config.js -> theme.extend
module.exports = {
  colors: {
    mm: {
      ink: '#16181D', graphite: '#5B5F68', mist: '#E2E4DF', paper: '#F2F3EF',
      signal: '#3A5BD9', 'signal-dark': '#7D96FF', raised: '#22252C',
      running: '#1F8A5B', warning: '#B7791F', blocked: '#C23B3B',
    },
  },
  fontFamily: {
    sans: ['Geist', '-apple-system', 'BlinkMacSystemFont', 'Helvetica Neue', 'sans-serif'],
    mono: ['Geist Mono', 'ui-monospace', 'SF Mono', 'Menlo', 'monospace'],
  },
  borderRadius: { sm: '6px', md: '10px', lg: '16px' },
};
