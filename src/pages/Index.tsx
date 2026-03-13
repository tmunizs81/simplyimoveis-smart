import Navbar from "@/components/Navbar";
import HeroSection from "@/components/HeroSection";
import HighlightsSection from "@/components/HighlightsSection";
import CidadeAlphaSection from "@/components/CidadeAlphaSection";
import OpportunitiesSection from "@/components/OpportunitiesSection";
import AboutSection from "@/components/AboutSection";
import ContactSection from "@/components/ContactSection";
import Footer from "@/components/Footer";
import ChatWidget from "@/components/ChatWidget";

const Index = () => {
  return (
    <div className="min-h-screen bg-background">
      <Navbar />
      <HeroSection />
      <HighlightsSection />
      <CidadeAlphaSection />
      <OpportunitiesSection />
      <AboutSection />
      <ContactSection />
      <Footer />
      <ChatWidget />
    </div>
  );
};

export default Index;
