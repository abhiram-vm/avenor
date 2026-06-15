import React from 'react'
import { useIntersectionObserver } from '../hooks/useIntersectionObserver'
import '../styles/features.css'

const FeatureCard = ({ icon, title, description, index }) => {
  const [ref, isVisible] = useIntersectionObserver()

  return (
    <div
      ref={ref}
      className={`feature-card scroll-scale stagger-${index + 1} ${isVisible ? 'in-view' : ''}`}
    >
      <div className="feature-icon">{icon}</div>
      <h3 className="feature-title">{title}</h3>
      <p className="feature-description">{description}</p>
    </div>
  )
}

const Features = () => {
  const features = [
    {
      icon: '⚡',
      title: 'Capture Bar',
      description: 'Natural language task capture. Type "Call John tomorrow 2pm" and Avenor parses it automatically.'
    },
    {
      icon: '🎨',
      title: 'Four Themes',
      description: 'Stark Dark, Stark Light, Calm Earth, and Liquid Glass. Sophisticated designs tailored to your preference.'
    },
    {
      icon: '📱',
      title: 'Smart Widgets',
      description: 'Lock screen and Today widgets. Quick access to your tasks without opening the app.'
    },
    {
      icon: '✨',
      title: 'Live Activities',
      description: 'Dynamic Island support. Watch your tasks count down in real-time on your lock screen.'
    }
  ]

  return (
    <section className="features">
      <div className="container">
        <div className="features-header">
          <h2>Designed for You</h2>
          <p>Everything you need to capture, organize, and own your goals.</p>
        </div>

        <div className="features-grid">
          {features.map((feature, idx) => (
            <FeatureCard
              key={idx}
              {...feature}
              index={idx}
            />
          ))}
        </div>
      </div>
    </section>
  )
}

export default Features
