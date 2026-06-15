import React, { useState } from 'react'
import { useIntersectionObserver } from '../hooks/useIntersectionObserver'
import '../styles/cta.css'

const CTA = () => {
  const [ref, isVisible] = useIntersectionObserver()
  const [email, setEmail] = useState('')
  const [isSubmitting, setIsSubmitting] = useState(false)
  const [submitStatus, setSubmitStatus] = useState(null)

  const handleEmailSubmit = async (e) => {
    e.preventDefault()

    if (!email) return

    setIsSubmitting(true)

    // Simulate API call (in production, connect to MailerLite, Convertkit, etc.)
    setTimeout(() => {
      setSubmitStatus('success')
      setEmail('')
      setIsSubmitting(false)

      setTimeout(() => {
        setSubmitStatus(null)
      }, 3000)
    }, 1000)
  }

  return (
    <section ref={ref} className={`cta ${isVisible ? 'in-view' : ''}`}>
      <div className="cta-content">
        <div className="cta-text scroll-slide-up">
          <h2>Ready to take back your time?</h2>
          <p>Avenor is available now on iOS. Download today and start capturing your thoughts intentionally.</p>
        </div>

        <div className="cta-buttons scroll-slide-up">
          <button
            className="btn btn-primary btn-large"
            onClick={() => window.open('https://apps.apple.com', '_blank')}
          >
            Download on App Store
          </button>
        </div>

        <div className="cta-divider">
          <span>or</span>
        </div>

        <form onSubmit={handleEmailSubmit} className="email-form scroll-slide-up">
          <input
            type="email"
            placeholder="Enter your email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            disabled={isSubmitting}
            className="email-input"
          />
          <button
            type="submit"
            className="btn btn-secondary btn-large"
            disabled={isSubmitting}
          >
            {isSubmitting ? 'Subscribing...' : 'Get Notified'}
          </button>

          {submitStatus === 'success' && (
            <div className="success-message">
              ✓ Check your inbox for a confirmation email!
            </div>
          )}
        </form>

        <p className="cta-footer">No spam. Unsubscribe anytime.</p>
      </div>

      {/* Background decorative elements */}
      <div className="cta-background">
        <div className="accent-circle accent-1"></div>
        <div className="accent-circle accent-2"></div>
      </div>
    </section>
  )
}

export default CTA
