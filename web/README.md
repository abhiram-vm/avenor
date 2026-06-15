# Avenor Premium Product Showcase Website

A minimalist, refined dark-mode marketing website for Avenor, an iOS productivity app. Built with React, Vite, and vanilla CSS with sophisticated scroll animations.

## Features

✨ **Premium Aesthetic**
- Dark mode design inspired by Linear, Vercel, and Arc Browser
- Deep black canvas (`#0a0a0c`) with electric cyan accents (`#00d9ff`)
- Refined typography with serif headlines and clean body fonts
- Generous whitespace and intentional design

🎬 **Sophisticated Animations**
- Morphing SVG hero background that transforms on scroll
- Parallax depth layers for immersive feel
- Staggered card reveals with asymmetric scaling
- Letter-by-letter text reveals with smooth easing
- Intersection Observer for performance-optimized scroll triggers
- 60fps animations using CSS transforms only

📱 **Responsive Design**
- Desktop-first approach with full mobile optimization
- Adaptive animations for different device capabilities
- Touch-friendly interactions on mobile
- Optimized typography scaling

🚀 **Performance**
- Vite for fast HMR and optimized builds
- CSS containment for rendering performance
- GPU-accelerated transforms
- No external animation libraries (pure CSS + vanilla JS)

## Project Structure

```
web/
├── public/               # Static assets
├── src/
│   ├── components/      # React components
│   │   ├── Hero.jsx     # Full-viewport hero with morphing SVG
│   │   ├── Features.jsx # 4-card feature showcase
│   │   ├── Pricing.jsx  # Free tier + future pricing tiers
│   │   └── CTA.jsx      # Final call-to-action
│   ├── styles/          # CSS modules
│   │   ├── tokens.css   # Design system (colors, typography, spacing)
│   │   ├── base.css     # Global styles and resets
│   │   ├── animations.css # Keyframe animations
│   │   ├── hero.css
│   │   ├── features.css
│   │   ├── pricing.css
│   │   └── cta.css
│   ├── hooks/          # Custom React hooks
│   │   ├── useIntersectionObserver.js
│   │   └── useScrollPosition.js
│   ├── App.jsx         # Root component
│   └── main.jsx        # Entry point
├── index.html          # HTML template
├── vite.config.js      # Vite configuration
├── package.json        # Dependencies
└── .gitignore
```

## Getting Started

### Prerequisites
- Node.js 16+ and npm/pnpm/yarn

### Installation

```bash
# Navigate to web directory
cd web

# Install dependencies
npm install
# or
pnpm install
# or
yarn install
```

### Development

```bash
npm run dev
```

Starts the Vite dev server at http://localhost:3000 with hot module replacement.

### Build

```bash
npm run build
```

Creates an optimized production build in the `dist/` directory.

```bash
npm run preview
```

Preview the production build locally.

## Design System

### Colors
- **Canvas:** `#0a0a0c` (deep black)
- **Surface:** `#101013` (card backgrounds)
- **Accent Primary:** `#00d9ff` (cyan for CTAs and highlights)
- **Accent Secondary:** `#a78bfa` (purple, for visual depth)
- **Text Primary:** `#ffffff` (white)
- **Text Secondary:** `#a0a0a3` (subtle gray)
- **Borders:** `rgba(255, 255, 255, 0.1)` (hairline white)

### Typography
- **Headlines:** Georgia (serif), 48–72px
- **Body:** System fonts (-apple-system, Segoe UI), 14–16px
- **Line Heights:** Tight (1.2), Normal (1.5), Relaxed (1.8)

### Spacing Scale
- `--space-xs: 4px`
- `--space-sm: 8px`
- `--space-md: 16px`
- `--space-lg: 24px`
- `--space-xl: 32px`
- `--space-2xl: 48px`
- `--space-3xl: 64px`

## Scroll Animations

### Hero Section
- **Morphing SVG:** Abstract blob shape rotates and warps as user scrolls
- **Parallax Layers:** 3 background layers move at different speeds
- **Text Reveals:** Headline words appear sequentially with staggered timing
- **Fade Out:** Hero section fades as user scrolls down

### Features Cards
- **Staggered Scale:** Cards scale in with 100ms stagger delays
- **Asymmetric Transform:** Each card uses different scale ratios for depth
- **3D Hover:** Subtle 3D rotation effect on hover with perspective
- **Glow Effect:** Accent color highlights on interaction

### Pricing & CTA
- **Scroll Fade:** Elements fade in as they enter the viewport
- **Slide Up:** Elements slide up from below with smooth timing
- **Decorative Elements:** Subtle accent circles with blur for visual interest

## Key Components

### useIntersectionObserver Hook
Custom hook for scroll-triggered animations using Intersection Observer API.

```jsx
const [ref, isVisible] = useIntersectionObserver()

return (
  <div ref={ref} className={`component ${isVisible ? 'in-view' : ''}`}>
    Content
  </div>
)
```

### useScrollPosition Hook
Tracks scroll position for parallax and other scroll-dependent effects.

```jsx
const scrollY = useScrollPosition()
```

## Email Signup Integration

The CTA section includes a functional email signup form. To connect it to an email service:

1. **MailerLite:** Create account at mailerlite.com
2. **Convertkit:** Use their embedded forms API
3. **Custom Backend:** Connect to your own API endpoint

Currently uses a simulated 1-second delay. Update `handleEmailSubmit()` in `CTA.jsx` to add your service.

## Performance Optimization

- **CSS Containment:** `contain: layout paint` on animated elements
- **Will-Change:** Used sparingly on high-frequency animations
- **GPU Acceleration:** Only transform and opacity are animated
- **Debouncing:** Scroll events use Intersection Observer
- **Mobile Optimization:** Simplified animations on lower-end devices

## Deployment

### Vercel (Recommended)

```bash
npm install -g vercel
vercel
```

### GitHub Pages

```bash
npm run build
# Deploy dist/ folder to GitHub Pages
```

### Other Platforms
- Netlify: Connect repository and set build command to `npm run build`
- AWS S3 + CloudFront: Upload `dist/` folder
- Traditional hosting: Upload `dist/` folder via FTP

## Browser Support

- Chrome/Edge: Full support (latest 2 versions)
- Firefox: Full support (latest 2 versions)
- Safari: Full support (iOS 15+, macOS 12+)
- Mobile browsers: Optimized experience

## Future Enhancements

- [ ] Dark/Light theme toggle
- [ ] Additional testimonials section
- [ ] Animated app screenshots
- [ ] Analytics integration (Vercel Analytics, Plausible)
- [ ] Newsletter email integration
- [ ] Blog/resources section
- [ ] Legal pages (privacy, terms)

## Notes for Developers

- **No external animation libraries:** All animations use CSS and vanilla JS
- **Performance first:** Tested for 60fps on devices with throttled performance
- **Responsive mobile:** Mobile experience is not just scaled-down desktop
- **Accessibility:** ARIA labels, semantic HTML, keyboard navigation
- **SEO ready:** Semantic structure, meta tags, fast loading

## License

This website is part of the Avenor project. See main LICENSE file.

---

**Built with ❤️ for Avenor**
