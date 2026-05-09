import { LandingNav } from './components/landing-nav'
import { HeroSection } from './components/hero-section'
import { ArchitectureSection } from './components/architecture-section'
import { FeaturesSection } from './components/features-section'
import { QuickStartSection } from './components/quick-start-section'
import { CtaSection } from './components/cta-section'
import { LandingFooter } from './components/landing-footer'

export function LandingPage() {
  return (
    <div className="fixed inset-0 overflow-y-auto bg-[#0a0a0b] text-[#e4e4e7] antialiased">
      {/* Background gradient */}
      <div className="fixed inset-0 pointer-events-none z-0">
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_80%_60%_at_50%_-20%,rgba(16,185,129,0.04),transparent_70%)]" />
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_50%_40%_at_80%_80%,rgba(6,182,212,0.03),transparent_70%)]" />
      </div>

      <div className="relative z-[1] max-w-[960px] mx-auto px-6">
        <LandingNav />
        <HeroSection />
      </div>

      <div className="relative z-[1]">
        <ArchitectureSection />
        <FeaturesSection />
        <QuickStartSection />
        <CtaSection />
        <LandingFooter />
      </div>
    </div>
  )
}
