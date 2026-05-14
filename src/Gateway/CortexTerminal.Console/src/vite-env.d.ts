/// <reference types="vite/client" />

declare namespace React.JSX {
  interface IntrinsicElements {
    'altcha-widget': React.DetailedHTMLProps<
      React.HTMLAttributes<HTMLElement> & {
        challengeurl?: string
        name?: string
        hidelogo?: boolean
        hidefooter?: boolean
      },
      HTMLElement
    >
  }
}
