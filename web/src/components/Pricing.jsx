import React from 'react'
import { useIntersectionObserver } from '../hooks/useIntersectionObserver'
import '../styles/pricing.css'

const PricingCard = ({ tier, price, description, features, isFree, isComingSoon }) => {
  const [ref, isVisible] = useIntersectionObserver()

  return (
    <div
      ref={ref}
      className={`pricing-card ${isFree ? 'featured' : ''} ${isComingSoon ? 'coming-soon' : ''} scroll-scale ${isVisible ? 'in-view' : ''}`}
    >
      {isComingSoon && <div className="badge">Coming Soon</div>}

      <div className="pricing-header">
        <h3 className="pricing-tier">{tier}</h3>
        {price && (
          <div className="pricing-amount">
            <span className="currency">$</span>
            <span className="amount">{price}</span>
            <span className="period">/month</span>
          </div>
        )}
      </div>

      <p className="pricing-description">{description}</p>

      <ul className="pricing-features">
        {features.map((feature, idx) => (
          <li key={idx} className="feature-item">
            <svg width="20" height="20" viewBox="0 0 20 20" fill="none">
              <path
                d="M17 6L7.5 16L3 11.5"
                stroke="currentColor"
                strokeWidth="2"
                strokeLinecap="round"
                strokeLinejoin="round"
              />
            </svg>
            <span>{feature}</span>
          </li>
        ))}
      </ul>

      <button className={`btn ${isFree ? 'btn-primary' : 'btn-secondary'}`}>
        {isComingSoon ? 'Notify Me' : isFree ? 'Download Now' : 'Get Started'}
      </button>
    </div>
  )
}

const Pricing = () => {
  const pricingTiers = [
    {
      tier: 'Free',
      price: 0,
      description: 'Everything you need to capture and organize your life.',
      features: [
        'Unlimited tasks, notes, and goals',
        'Four beautiful themes',
        'Today widget',
        'Lock screen widgets',
        'Natural language capture',
        'CloudKit sync'
      ],
      isFree: true,
      isComingSoon: false
    },
    {
      tier: 'Premium',
      price: null,
      description: 'Advanced features for power users.',
      features: [
        'Everything in Free',
        'Advanced goal tracking',
        'Custom templates',
        'Priority support',
        'Early access to new features'
      ],
      isFree: false,
      isComingSoon: true
    },
    {
      tier: 'Pro',
      price: null,
      description: 'The ultimate productivity suite.',
      features: [
        'Everything in Premium',
        'Team collaboration',
        'Advanced analytics',
        'API access',
        'Custom theming'
      ],
      isFree: false,
      isComingSoon: true
    }
  ]

  return (
    <section className="pricing">
      <div className="container">
        <div className="pricing-header-section">
          <h2>Simple, Transparent Pricing</h2>
          <p>Start free. Upgrade when you're ready.</p>
        </div>

        <div className="pricing-grid">
          {pricingTiers.map((tier, idx) => (
            <PricingCard key={idx} {...tier} />
          ))}
        </div>
      </div>
    </section>
  )
}

export default Pricing
