'use client';

import Link from 'next/link';
import { useState, useEffect } from 'react';

export default function Navbar() {
  const [isScrolled, setIsScrolled] = useState(false);

  useEffect(() => {
    const handleScroll = () => {
      setIsScrolled(window.scrollY > 50);
    };

    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  const handleNavClick = (e: React.MouseEvent<HTMLAnchorElement>, sectionId: string) => {
    e.preventDefault();
    const element = document.getElementById(sectionId);
    if (element) {
      element.scrollIntoView({ behavior: 'smooth' });
    }
  };

  const navItems = [
    { id: 'features', label: 'Features' },
    { id: 'download', label: 'Download' },
    { id: 'contact', label: 'Contact' },
  ];

  return (
    <nav 
      className={`sticky top-0 z-50 border-b border-gray-200 bg-white transition-all duration-300 ${
        isScrolled ? 'shadow-md' : ''
      }`}
    >
      <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-4 sm:px-6 lg:px-8">
        <Link 
          href="/" 
          className="flex items-center space-x-2 transition-transform duration-300 hover:scale-105"
        >
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-blue-600 transition-transform duration-300 hover:rotate-12">
            <span className="font-bold text-white">AC</span>
          </div>
          <span className="text-xl font-bold text-gray-900">ApexCardio</span>
        </Link>
        <div className="hidden space-x-8 md:flex">
          {navItems.map((item, index) => (
            <a
              key={item.id}
              href={`#${item.id}`}
              onClick={(e) => handleNavClick(e, item.id)}
              className="group relative text-gray-700 transition-colors duration-300 hover:text-blue-600"
              style={{
                animation: `slideInNavButton 0.5s ease-out ${index * 0.1}s forwards`,
                opacity: 0,
              }}
            >
              <span className="relative inline-block">
                {item.label}
                <span 
                  className="absolute bottom-0 left-0 h-0.5 w-0 bg-linear-to-r from-blue-600 to-cyan-500 transition-all duration-300 group-hover:w-full"
                />
              </span>
            </a>
          ))}
        </div>
      </div>

      <style jsx>{`
        @keyframes slideInNavButton {
          from {
            opacity: 0;
            transform: translateY(-10px);
          }
          to {
            opacity: 1;
            transform: translateY(0);
          }
        }
      `}</style>
    </nav>
  );
}