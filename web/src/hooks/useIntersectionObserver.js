import React, { useEffect, useRef, useState } from 'react'

export const useIntersectionObserver = (options = {}) => {
  const ref = useRef(null)
  const [isVisible, setIsVisible] = useState(false)

  useEffect(() => {
    if (!ref.current) return

    const observer = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting) {
        setIsVisible(true)
        // Only observe once for initial animations
        observer.unobserve(entry.target)
      }
    }, {
      threshold: 0.3,
      ...options
    })

    observer.observe(ref.current)

    return () => observer.disconnect()
  }, [options])

  return [ref, isVisible]
}

export default useIntersectionObserver
