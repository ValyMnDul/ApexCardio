'use client';

import Navbar from '../components/Navbar';
import Footer from '../components/Footer';
import { useState } from 'react';

export default function FAQ() {
  const [openItems, setOpenItems] = useState<number[]>([]);

  const faqs = [
    {
      question: 'How accurate is ApexCardio?',
      answer: 'ApexCardio uses advanced algorithms and high-precision sensors to provide heart rate measurements with medical-grade accuracy. Our system is validated against clinical monitors and provides consistent readings across all devices.'
    },
    {
      question: 'Is my health data safe?',
      answer: 'Yes, your data is encrypted using enterprise-grade security protocols. We never share your health information without explicit consent and comply with HIPAA and GDPR regulations.'
    },
    {
      question: 'Can I use ApexCardio for free?',
      answer: 'Yes. ApexCardio is free to use and includes heart rate monitoring, daily summaries, and 7-day data history for every user.'
    },
    {
      question: 'How do I sync my data across devices?',
      answer: 'Once you create an account, your data automatically syncs across all devices where you&apos;re logged in. This happens in real-time when you&apos;re connected to the internet.'
    },
    {
      question: 'What devices does ApexCardio support?',
      answer: 'ApexCardio is available on iOS 14.0+ and Android 8.0+. It works with most modern smartwatches and fitness trackers via Bluetooth connectivity.'
    },
    {
      question: 'Can I export my health data?',
      answer: 'Yes, you can export your health reports in PDF format. This is useful for sharing with healthcare professionals.'
    }
  ];

  const toggleItem = (idx: number) => {
    setOpenItems(prev =>
      prev.includes(idx) ? prev.filter(i => i !== idx) : [...prev, idx]
    );
  };

  return (
    <div className="min-h-screen bg-white">
      <Navbar />

      {/* Hero Section */}
      <section className="bg-linear-to-br from-blue-50 to-white py-20 px-4">
        <div className="max-w-4xl mx-auto text-center">
          <h1 className="text-5xl font-bold text-gray-900 mb-6">Frequently Asked Questions</h1>
          <p className="text-xl text-gray-600">Find answers to common questions about ApexCardio.</p>
        </div>
      </section>

      {/* FAQs */}
      <section className="py-20 px-4 bg-white">
        <div className="max-w-3xl mx-auto">
          <div className="space-y-4">
            {faqs.map((faq, idx) => (
              <div
                key={idx}
                className="border border-gray-200 rounded-lg overflow-hidden hover:border-blue-400 transition"
              >
                <button
                  onClick={() => toggleItem(idx)}
                  className="w-full p-6 flex items-center justify-between bg-white hover:bg-blue-50 transition"
                >
                  <h3 className="text-lg font-semibold text-gray-900 text-left">{faq.question}</h3>
                  <svg
                    className={`w-6 h-6 text-blue-600 transition-transform ${
                      openItems.includes(idx) ? 'rotate-180' : ''
                    }`}
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M19 14l-7 7m0 0l-7-7m7 7V3"
                    />
                  </svg>
                </button>
                {openItems.includes(idx) && (
                  <div className="p-6 bg-blue-50 border-t border-gray-200">
                    <p className="text-gray-600 leading-relaxed">{faq.answer}</p>
                  </div>
                )}
              </div>
            ))}
          </div>
        </div>
      </section>

      <Footer />
    </div>
  );
}
