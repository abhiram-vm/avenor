import React from 'react'
import './styles/base.css'
import Hero from './components/Hero'
import Features from './components/Features'
import Pricing from './components/Pricing'
import CTA from './components/CTA'

function App() {
  return (
    <main>
      <Hero />
      <Features />
      <Pricing />
      <CTA />
    </main>
  )
}

export default App
