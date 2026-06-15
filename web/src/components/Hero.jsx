import React, { useState, useEffect } from 'react'
import { useScrollPosition } from '../hooks/useScrollPosition'
import '../styles/hero.css'

const AnimatedMorphingSVG = ({ scrollY }) => {
  // Calculate rotation based on scroll position
  const rotation = Math.min(scrollY * 0.5, 45)
  const scale = 1 + scrollY * 0.0005

  return (
    <svg
      viewBox="0 0 400 400"
      className="morphing-svg"
      style={{
        transform: `rotate(${rotation}deg) scale(${scale})`,
      }}
    >
      <defs>
        <filter id="glow">
          <feGaussianBlur stdDeviation="4" result="coloredBlur"/>
          <feMerge>
            <feMergeNode in="coloredBlur"/>
            <feMergeNode in="SourceGraphic"/>
          </feMerge>
        </filter>
      </defs>

      {/* Background gradient circles (parallax layers) */}
      <circle
        cx="200"
        cy="200"
        r="180"
        fill="none"
        stroke="rgba(0, 217, 255, 0.05)"
        strokeWidth="1"
        opacity={1 - scrollY * 0.002}
      />
      <circle
        cx="200"
        cy="200"
        r="150"
        fill="none"
        stroke="rgba(0, 217, 255, 0.08)"
        strokeWidth="1"
        opacity={1 - scrollY * 0.003}
      />

      {/* Morphing blob */}
      <path
        d="M 200 120 Q 280 140 290 200 Q 280 260 200 280 Q 120 260 110 200 Q 120 140 200 120 Z"
        fill="rgba(0, 217, 255, 0.1)"
        filter="url(#glow)"
        style={{
          animation: 'morphBlob 8s ease-in-out infinite',
        }}
      />

      {/* Accent lines */}
      <line
        x1="200"
        y1="100"
        x2="200"
        y2="300"
        stroke="rgba(0, 217, 255, 0.15)"
        strokeWidth="1"
        opacity={0.5 + scrollY * 0.0005}
      />
      <line
        x1="100"
        y1="200"
        x2="300"
        y2="200"
        stroke="rgba(0, 217, 255, 0.15)"
        strokeWidth="1"
        opacity={0.5 + scrollY * 0.0005}
      />
    </svg>
  )
}

const Hero = () => {
  const scrollY = useScrollPosition()
  const [lettersVisible, setLettersVisible] = useState(false)

  useEffect(() => {
    setTimeout(() => setLettersVisible(true), 300)
  }, [])

  // Parallax offsets for background layers
  const parallax1 = scrollY * 0.5
  const parallax2 = scrollY * 0.3
  const parallax3 = scrollY * 0.1

  // Fade out hero as user scrolls
  const heroOpacity = Math.max(0, 1 - scrollY / 500)

  const headline = "The productivity app designed for intention"
  const subheading = "Capture your thoughts. Organize your ideas. Own your goals."

  return (
    <section className="hero" style={{ opacity: heroOpacity }}>
      {/* Parallax Background Layers */}
      <div className="parallax-layer parallax-1" style={{ transform: `translateY(${parallax1}px)` }}>
        <AnimatedMorphingSVG scrollY={scrollY} />
      </div>

      <div className="parallax-layer parallax-2" style={{ transform: `translateY(${parallax2}px)` }} />
      <div className="parallax-layer parallax-3" style={{ transform: `translateY(${parallax3}px)` }} />

      {/* Content */}
      <div className="hero-content">
        <div className="hero-headline">
          <h1 className="hero-title">
            {headline.split(' ').map((word, idx) => (
              <span
                key={idx}
                className={`word-reveal ${lettersVisible ? 'reveal' : ''}`}
                style={{
                  transitionDelay: `${idx * 0.08}s`,
                }}
              >
                {word}&nbsp;
              </span>
            ))}
          </h1>
        </div>

        <p className="hero-subtitle">
          {subheading}
        </p>

        <div className="hero-cta">
          <button
            className="btn btn-primary"
            onClick={() => window.open('https://apps.apple.com', '_blank')}
          >
            Download on App Store
          </button>
          <button className="btn btn-secondary">
            Get notified
          </button>
        </div>

        <div className="hero-scroll-indicator">
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor">
            <path d="M12 5v14M5 12l7 7 7-7" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </div>
      </div>
    </section>
  )
}

export default Hero
