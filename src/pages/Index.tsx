import { lazy, Suspense } from "react";
import Navbar from "@/components/Navbar";
import HeroSection from "@/components/HeroSection";
import TrustSection from "@/components/TrustSection";
import Footer from "@/components/Footer";
import ChatWidget from "@/components/ChatWidget";
import WhatsAppButton from "@/components/WhatsAppButton";

const HighlightsSection = lazy(() => import("@/components/HighlightsSection"));
const OpportunitiesSection = lazy(() => import("@/components/OpportunitiesSection"));
const TestimonialsSection = lazy(() => import("@/components/TestimonialsSection"));
const AboutSection = lazy(() => import("@/components/AboutSection"));
const ContactSection = lazy(() => import("@/components/ContactSection"));

const SectionFallback = () => (
  <div className="py-20 flex items-center justify-center">
    <div className="w-6 h-6 border-2 border-primary/30 border-t-primary rounded-full animate-spin" />
  </div>
);

const Index = () => {
  return (
    <div className="min-h-screen bg-background">
      <Navbar />
      <HeroSection />
      <TrustSection />
      <Suspense fallback={<SectionFallback />}>
        <HighlightsSection />
      </Suspense>
      <Suspense fallback={<SectionFallback />}>
        <OpportunitiesSection />
      </Suspense>
      <Suspense fallback={<SectionFallback />}>
        <TestimonialsSection />
      </Suspense>
      <Suspense fallback={<SectionFallback />}>
        <AboutSection />
      </Suspense>
      <Suspense fallback={<SectionFallback />}>
        <ContactSection />
      </Suspense>
      <Footer />
      <ChatWidget />
      <WhatsAppButton />
    </div>
  );
};

export default Index;
