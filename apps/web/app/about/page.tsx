"use client";

import Navbar from '../components/Navbar';
import Footer from '../components/Footer';

export default function About() {
  return (
    <div className="min-h-screen bg-white">
      <Navbar />

      {/* Hero Section */}
      <section className="bg-linear-to-br from-blue-50 to-white py-20 px-4">
        <div className="max-w-4xl mx-auto">
          <h1 className="text-5xl font-bold text-gray-900 mb-6">About ApexCardio</h1>
          <p className="text-xl text-gray-600 leading-relaxed">
            We are dedicated to empowering individuals to take control of their cardiovascular health through advanced technology and personalized insights.
          </p>
        </div>
      </section>

      {/* Content Sections */}
      <section className="py-16 px-4 bg-white">
        <div className="max-w-4xl mx-auto space-y-12">
          <div>
            <h2 className="text-3xl font-bold text-gray-900 mb-4">Our Mission</h2>
            <p className="text-gray-600 leading-relaxed mb-4">
              ApexCardio&apos;s mission is to make advanced heart health monitoring accessible to everyone. We believe that real-time cardiovascular insights should not be limited to healthcare professionals, but available to anyone who wants to take control of their health journey.
            </p>
            <p className="text-gray-600 leading-relaxed">
              By combining cutting-edge technology with intuitive design, we&apos;re helping millions of users understand their heart better and make informed decisions about their wellness.
            </p>
          </div>

          <div>
            <h2 className="text-3xl font-bold text-gray-900 mb-4">Our Values</h2>
            <div className="grid md:grid-cols-3 gap-8">
              <div className="p-6 bg-blue-50 rounded-xl">
                <h3 className="font-bold text-gray-900 mb-2">Precision</h3>
                <p className="text-gray-600 text-sm">We use the latest sensors and algorithms to ensure accurate heart rate monitoring and health insights.</p>
              </div>
              <div className="p-6 bg-blue-50 rounded-xl">
                <h3 className="font-bold text-gray-900 mb-2">Privacy</h3>
                <p className="text-gray-600 text-sm">Your health data is sacred. We encrypt everything and never share your information without consent.</p>
              </div>
              <div className="p-6 bg-blue-50 rounded-xl">
                <h3 className="font-bold text-gray-900 mb-2">Accessibility</h3>
                <p className="text-gray-600 text-sm">Our app is designed to be easy to use for everyone, regardless of technical background.</p>
              </div>
            </div>
          </div>

          <div>
            <h2 className="text-3xl font-bold text-gray-900 mb-4">Our Technology</h2>
            <p className="text-gray-600 leading-relaxed">
              ApexCardio leverages advanced machine learning algorithms and real-time data processing to deliver accurate heart rate measurements and predictive health insights. Our platform is built on enterprise-grade infrastructure ensuring 99.9% uptime and seamless synchronization across all your devices.
            </p>
          </div>
        </div>
      </section>

      <Footer />
    </div>
  );
}
