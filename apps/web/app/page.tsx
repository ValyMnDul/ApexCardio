'use client';

import Image from 'next/image';
import { useState } from 'react';
import Navbar from './components/Navbar';
import Footer from './components/Footer';

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
      <Navbar />

      {/* Hero Section */}
      <section className="bg-linear-to-br from-blue-50 to-white pt-20 pb-24 px-4">
        <div className="max-w-6xl mx-auto">
          <div className="grid md:grid-cols-2 gap-12 items-center">
            <div>
              <div className="inline-flex items-center rounded-full border border-blue-200 bg-white px-4 py-2 text-sm font-medium text-blue-700 shadow-sm mb-6">
                Cardiovascular tracking, simplified.
              </div>
              <h1 className="text-5xl md:text-6xl font-bold text-gray-900 mb-6 leading-tight">
                Track Your Heart Health with Precision
              </h1>
              <p className="text-xl text-gray-600 mb-8 leading-relaxed">
                ApexCardio gives you real-time insights into your cardiovascular health. Monitor your heart rate, track fitness metrics, and achieve your wellness goals with advanced analytics.
              </p>
              <div className="flex flex-col items-center gap-4 sm:flex-row sm:items-stretch sm:justify-start">
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
                <div className="inline-block p-6 bg-white rounded-full mb-4 shadow-sm">
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
              <div key={idx} className="rounded-xl border border-gray-200 p-8 transition hover:border-blue-400 hover:shadow-lg">
                <div className="mb-4 flex h-10 w-10 items-center justify-center rounded-lg bg-blue-100 text-blue-600">
                  {feature.icon}
                </div>
                <h3 className="mb-3 text-xl font-bold text-gray-900">{feature.title}</h3>
                <p className="leading-relaxed text-gray-600">{feature.description}</p>
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
      <Footer />
    </div>
  );
}