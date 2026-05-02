'use client';

import Image from 'next/image';
import { useState } from 'react';
import { FaInstagram, FaGithub, FaFacebook } from "react-icons/fa";
import { SiTiktok } from "react-icons/si";

export default function Main() {
  const [formStatus, setFormStatus] = useState('');

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setFormStatus('Sending...');
    
    const form = e.currentTarget;
    const formData = new FormData(form);

    try {
      const response = await fetch('https://formspree.io/f/xpqbwkzp', {
        method: 'POST',
        body: formData,
        headers: {
          Accept: 'application/json',
        },
      });

      if (response.ok) {
        setFormStatus('Thank you! We will contact you soon.');
        form.reset();
        setTimeout(() => setFormStatus(''), 3000);
      } else {
        setFormStatus('Something went wrong. Please try again.');
      }
    } catch {
      setFormStatus('Error sending message. Please try again.');
    }
  };

  return (
    <div className="min-h-screen bg-white">
      {/* Navigation */}
      <nav className="sticky top-0 z-50 bg-white border-b border-gray-200">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 py-4 flex items-center justify-between">
          <div className="flex items-center space-x-2">
            <div className="w-8 h-8 bg-blue-600 rounded-lg flex items-center justify-center">
              <span className="text-white font-bold">AC</span>
            </div>
            <span className="text-xl font-bold text-gray-900">ApexCardio</span>
          </div>
          <div className="hidden md:flex space-x-8">
            <a href="#features" className="text-gray-700 hover:text-blue-600 transition">Features</a>
            <a href="#download" className="text-gray-700 hover:text-blue-600 transition">Download</a>
            <a href="#contact" className="text-gray-700 hover:text-blue-600 transition">Contact</a>
          </div>
        </div>
      </nav>

      {/* Hero Section */}
      <section className="bg-linear-to-br from-blue-50 to-white pt-20 pb-24 px-4">
        <div className="max-w-6xl mx-auto">
          <div className="grid md:grid-cols-2 gap-12 items-center">
            <div>
              <h1 className="text-5xl md:text-6xl font-bold text-gray-900 mb-6 leading-tight">
                Track Your Heart Health with Precision
              </h1>
              <p className="text-xl text-gray-600 mb-8 leading-relaxed">
                ApexCardio gives you real-time insights into your cardiovascular health. Monitor your heart rate, track fitness metrics, and achieve your wellness goals with advanced analytics.
              </p>
              <div className="flex flex-col sm:flex-row gap-4">
                <a href="#download" className="bg-blue-600 text-white px-8 py-4 rounded-lg font-semibold hover:bg-blue-700 transition transform hover:scale-105 text-center">
                  Download Now
                </a>
                <a href="/about" className="border-2 border-blue-600 text-blue-600 px-8 py-4 rounded-lg font-semibold hover:bg-blue-50 transition text-center">
                  Learn More
                </a>
              </div>
            </div>
            <div className="bg-linear-to-br from-blue-100 to-blue-50 rounded-2xl aspect-square flex items-center justify-center">
              <div className="text-center">
                <div className="inline-block p-6 bg-white rounded-full mb-4">
                  <svg className="w-16 h-16 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
                  </svg>
                </div>
                <p className="text-gray-600 font-medium">Real-time Health Analytics</p>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Features Section */}
      <section id="features" className="py-20 px-4 bg-white">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-4xl md:text-5xl font-bold text-gray-900 mb-4">
              Powerful Features
            </h2>
            <p className="text-xl text-gray-600">
              Everything you need to monitor and improve your cardiovascular health
            </p>
          </div>

          <div className="grid md:grid-cols-3 gap-8">
            {[
              {
                title: 'Advanced Analytics',
                description: 'Detailed insights into your heart rate patterns, trends, and health metrics over time.',
                icon: (
                  <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
                  </svg>
                )
              },
              {
                title: 'Real-time Monitoring',
                description: 'Track your heart rate instantly with high-precision sensors and get immediate alerts.',
                icon: (
                  <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                  </svg>
                )
              },
              {
                title: 'Personalized Goals',
                description: 'Set custom fitness targets and receive tailored recommendations based on your data.',
                icon: (
                  <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" />
                  </svg>
                )
              },
              {
                title: 'Cross-Platform Sync',
                description: 'Seamlessly sync your data across all your devices for continuous monitoring.',
                icon: (
                  <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 18h.01M8 21h8a2 2 0 002-2V5a2 2 0 00-2-2H8a2 2 0 00-2 2v14a2 2 0 002 2z" />
                  </svg>
                )
              },
              {
                title: 'Smart Notifications',
                description: 'Stay informed with intelligent alerts for anomalies and important health milestones.',
                icon: (
                  <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9" />
                  </svg>
                )
              },
              {
                title: 'Privacy First',
                description: 'Your health data is encrypted and stored securely with enterprise-grade protection.',
                icon: (
                  <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z" />
                  </svg>
                )
              }
            ].map((feature, idx) => (
              <div key={idx} className="p-8 rounded-xl border border-gray-200 hover:border-blue-400 hover:shadow-lg transition">
                <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center text-blue-600 mb-4">
                  {feature.icon}
                </div>
                <h3 className="text-xl font-bold text-gray-900 mb-3">{feature.title}</h3>
                <p className="text-gray-600 leading-relaxed">{feature.description}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Download Section */}
      <section id="download" className="py-20 px-4 bg-gray-50">
        <div className="max-w-6xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-4xl md:text-5xl font-bold text-gray-900 mb-4">
              Download ApexCardio
            </h2>
            <p className="text-xl text-gray-600">
              Get the app on your favorite device and start tracking today
            </p>
          </div>

          <div className="grid md:grid-cols-2 gap-8 max-w-3xl mx-auto">
            {/* iOS */}
            <div className="bg-white rounded-2xl p-10 border-2 border-gray-200 hover:border-blue-600 transition flex flex-col h-full">
              <div className="flex flex-1 flex-col items-center text-center">
                <div className="mb-6 flex h-20 w-20 items-center justify-center overflow-hidden rounded-xl bg-white">
                  <Image
                    src="/apple.png"
                    alt="Apple logo"
                    width={80}
                    height={80}
                    className="block h-full w-full object-contain"
                    priority
                  />
                </div>
                <h3 className="text-2xl font-bold text-gray-900 mb-3">iPhone &amp; iPad</h3>
                <p className="text-gray-600 leading-relaxed">
                  Download ApexCardio from the Apple App Store and monitor your heart health on the go.
                </p>
              </div>
              <div className="w-full pt-8">
                <a 
                  href="https://apps.apple.com"
                  className="block w-full bg-gray-900 text-white py-4 rounded-lg font-semibold text-center hover:bg-gray-800 transition mb-3"
                >
                  Download on App Store
                </a>
                <p className="text-sm text-gray-500 text-center">Requires iOS 14.0 or later</p>
              </div>
            </div>

            {/* Android */}
            <div className="bg-white rounded-2xl p-10 border-2 border-gray-200 hover:border-blue-600 transition flex flex-col h-full">
              <div className="flex flex-1 flex-col items-center text-center">
                <div className="mb-6 flex h-20 w-20 items-center justify-center overflow-hidden rounded-xl bg-white">
                  <Image
                    src="/android.png"
                    alt="Android logo"
                    width={80}
                    height={80}
                    className="block h-full w-full object-contain"
                  />
                </div>
                <h3 className="text-2xl font-bold text-gray-900 mb-3">Android</h3>
                <p className="text-gray-600 leading-relaxed">
                  Get ApexCardio on Google Play Store for seamless heart monitoring on your Android device.
                </p>
              </div>
              <div className="w-full pt-8">
                <a 
                  href="https://play.google.com"
                  className="block w-full bg-green-600 text-white py-4 rounded-lg font-semibold text-center hover:bg-green-700 transition mb-3"
                >
                  Download on Google Play
                </a>
                <p className="text-sm text-gray-500 text-center">Requires Android 8.0 or later</p>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Contact Section */}
      <section id="contact" className="py-20 px-4 bg-white">
        <div className="max-w-2xl mx-auto">
          <div className="text-center mb-12">
            <h2 className="text-4xl md:text-5xl font-bold text-gray-900 mb-4">
              Get in Touch
            </h2>
            <p className="text-xl text-gray-600">
              Have questions? We&apos;d love to hear from you. Send us a message and we&apos;ll respond as soon as possible.
            </p>
          </div>

          <form onSubmit={handleSubmit} className="space-y-6">
            <div>
              <label htmlFor="name" className="block text-sm font-semibold text-gray-900 mb-2">
                Full Name
              </label>
              <input
                type="text"
                id="name"
                name="name"
                required
                className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100 transition"
                placeholder="Your name"
              />
            </div>

            <div>
              <label htmlFor="email" className="block text-sm font-semibold text-gray-900 mb-2">
                Email Address
              </label>
              <input
                type="email"
                id="email"
                name="email"
                required
                className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100 transition"
                placeholder="your@email.com"
              />
            </div>

            <div>
              <label htmlFor="subject" className="block text-sm font-semibold text-gray-900 mb-2">
                Subject
              </label>
              <input
                type="text"
                id="subject"
                name="subject"
                required
                className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100 transition"
                placeholder="What is this about?"
              />
            </div>

            <div>
              <label htmlFor="message" className="block text-sm font-semibold text-gray-900 mb-2">
                Message
              </label>
              <textarea
                id="message"
                name="message"
                required
                rows={6}
                className="w-full px-4 py-3 border border-gray-300 rounded-lg focus:outline-none focus:border-blue-600 focus:ring-2 focus:ring-blue-100 transition resize-none"
                placeholder="Your message..."
              />
            </div>

            {formStatus && (
              <div className={`p-4 rounded-lg ${formStatus.includes('Thank you') ? 'bg-green-50 text-green-700' : 'bg-blue-50 text-blue-700'}`}>
                {formStatus}
              </div>
            )}

            <button
              type="submit"
              className="w-full bg-blue-600 text-white py-4 rounded-lg font-semibold hover:bg-blue-700 transition"
            >
              Send Message
            </button>
          </form>
        </div>
      </section>

      {/* Footer */}
      <footer className="bg-gray-900 text-gray-300 py-16 px-4">
        <div className="max-w-6xl mx-auto">
          <div className="grid md:grid-cols-4 gap-8 mb-12">
            {/* Brand */}
            <div>
              <div className="flex items-center space-x-2 mb-4">
                <div className="w-8 h-8 bg-blue-600 rounded-lg flex items-center justify-center">
                  <span className="text-white font-bold text-sm">AC</span>
                </div>
                <span className="text-lg font-bold text-white">ApexCardio</span>
              </div>
              <p className="text-sm leading-relaxed">
                Advanced cardiovascular health monitoring for everyone.
              </p>
            </div>

            {/* Product */}
            <div>
              <h4 className="text-white font-semibold mb-4">Product</h4>
              <ul className="space-y-2 text-sm">
                <li><a href="#features" className="hover:text-blue-400 transition">Features</a></li>
                <li><a href="#download" className="hover:text-blue-400 transition">Download</a></li>
                <li><a href="/faq" className="hover:text-blue-400 transition">FAQ</a></li>
              </ul>
            </div>

            {/* Company */}
            <div>
              <h4 className="text-white font-semibold mb-4">Company</h4>
              <ul className="space-y-2 text-sm">
                <li><a href="/about" className="hover:text-blue-400 transition">About Us</a></li>
                <li><a href="#contact" className="hover:text-blue-400 transition">Contact</a></li>
                <li><a href="/blog" className="hover:text-blue-400 transition">Blog</a></li>
                <li><a href="/press" className="hover:text-blue-400 transition">Press</a></li>
              </ul>
            </div>

            {/* Social Media */}
            <div>
              <h4 className="text-white font-semibold mb-4">Follow Us</h4>
              <div className="flex space-x-4">
                <a
                  href="https://github.com"
                  className="p-2 bg-gray-800 rounded-lg hover:bg-blue-600 transition flex items-center justify-center text-white"
                  title="GitHub"
                  aria-label="GitHub"
                >
                  <FaGithub className="w-5 h-5" aria-hidden="true" />
                </a>

                <a
                  href="https://instagram.com"
                  className="p-2 bg-gray-800 rounded-lg hover:bg-pink-500 transition flex items-center justify-center text-white"
                  title="Instagram"
                  aria-label="Instagram"
                >
                  <FaInstagram className="w-5 h-5" aria-hidden="true" />
                </a>

                <a
                  href="https://tiktok.com"
                  className="p-2 bg-gray-800 rounded-lg hover:bg-black transition flex items-center justify-center text-white"
                  title="TikTok"
                  aria-label="TikTok"
                >
                  <SiTiktok className="w-5 h-5" aria-hidden="true" />
                </a>

                <a
                  href="https://facebook.com"
                  className="p-2 bg-gray-800 rounded-lg hover:bg-blue-700 transition flex items-center justify-center text-white"
                  title="Facebook"
                  aria-label="Facebook"
                >
                  <FaFacebook className="w-5 h-5" aria-hidden="true" />
                </a>
              </div>
            </div>
          </div>

          {/* Divider */}
          <div className="border-t border-gray-800 my-8"></div>

          {/* Bottom Section */}
          <div className="flex flex-col md:flex-row justify-between items-center text-sm text-gray-400">
            <p>&copy; 2026 ApexCardio. All rights reserved.</p>
            <div className="flex space-x-6 mt-4 md:mt-0">
              <a href="/privacy" className="hover:text-blue-400 transition">Privacy Policy</a>
              <a href="/terms" className="hover:text-blue-400 transition">Terms of Service</a>
              <a href="/cookies" className="hover:text-blue-400 transition">Cookie Policy</a>
            </div>
          </div>
        </div>
      </footer>
    </div>
  );
}