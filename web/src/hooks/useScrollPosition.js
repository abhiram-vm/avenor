import React, { useEffect, useRef } from 'react'

export const useScrollPosition = () => {
  const [scrollY, setScrollY] = React.useState(0)

  useEffect(() => {
    const handleScroll = () => {
      setScrollY(window.scrollY)
    }

    window.addEventListener('scroll', handleScroll, { passive: true })
    return () => window.removeEventListener('scroll', handleScroll)
  }, [])

  return scrollY
}

export default useScrollPosition
