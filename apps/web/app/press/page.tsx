'use client';

export default function Press() {
  return (
    <div className="min-h-screen bg-white">
      {/* Navigation */}
      <nav className="sticky top-0 z-50 bg-white border-b border-gray-200">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 lg:px-8 py-4 flex items-center justify-between">
          <a href="/" className="flex items-center space-x-2">
            <div className="w-8 h-8 bg-blue-600 rounded-lg flex items-center justify-center">
              <span className="text-white font-bold">AC</span>
            </div>
            <span className="text-xl font-bold text-gray-900">ApexCardio</span>
          </a>
          <div className="hidden md:flex space-x-8">
            <a href="/#features" className="text-gray-700 hover:text-blue-600 transition">Features</a>
            <a href="/#download" className="text-gray-700 hover:text-blue-600 transition">Download</a>
            <a href="/#contact" className="text-gray-700 hover:text-blue-600 transition">Contact</a>
          </div>
        </div>
      </nav>

      {/* Hero Section */}
      <section className="bg-linear-to-br from-blue-50 to-white py-20 px-4">
        <div className="max-w-4xl mx-auto text-center">
          <h1 className="text-5xl font-bold text-gray-900 mb-6">Press &amp; Media</h1>
          <p className="text-xl text-gray-600">Latest news and announcements from ApexCardio.</p>
        </div>
      </section>

      {/* Content */}
      <section className="py-20 px-4 bg-white">
        <div className="max-w-4xl mx-auto space-y-12">
          <div>
            <h2 className="text-3xl font-bold text-gray-900 mb-6">Latest Announcements</h2>
            
            <article className="border-l-4 border-blue-600 pl-6 mb-8 pb-8 border-b">
              <h3 className="text-2xl font-bold text-gray-900 mb-2">ApexCardio Expands Free Health Insights</h3>
              <p className="text-sm text-gray-500 mb-4">May 2024</p>
              <p className="text-gray-600 leading-relaxed">
                ApexCardio is excited to announce a major update that brings advanced analytics, clearer summaries, and more useful health insights to every user at no extra cost.
              </p>
            </article>

            <article className="border-l-4 border-blue-600 pl-6 mb-8 pb-8 border-b">
              <h3 className="text-2xl font-bold text-gray-900 mb-2">5 Million Users Milestone Reached</h3>
              <p className="text-sm text-gray-500 mb-4">April 2024</p>
              <p className="text-gray-600 leading-relaxed">
                We&apos;re thrilled to announce that ApexCardio has reached 5 million active users worldwide. This achievement represents our commitment to making cardiovascular health monitoring accessible to everyone.
              </p>
            </article>

            <article className="border-l-4 border-blue-600 pl-6">
              <h3 className="text-2xl font-bold text-gray-900 mb-2">ApexCardio Wins Health Innovation Award</h3>
              <p className="text-sm text-gray-500 mb-4">March 2024</p>
              <p className="text-gray-600 leading-relaxed">
                ApexCardio received the prestigious Health Innovation Award for its groundbreaking approach to real-time cardiovascular monitoring. The award recognizes our dedication to combining advanced technology with user-friendly design.
              </p>
            </article>
          </div>

          <div className="bg-blue-50 p-8 rounded-xl">
            <h3 className="text-2xl font-bold text-gray-900 mb-4">For Media Inquiries</h3>
            <p className="text-gray-600 mb-4">
              If you&apos;re interested in featuring ApexCardio in your publication or need additional information for your story, please reach out to our press team.
            </p>
            <a href="/#contact" className="inline-block bg-blue-600 text-white px-6 py-3 rounded-lg font-semibold hover:bg-blue-700 transition">
              Contact Press Team
            </a>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="bg-gray-900 text-gray-300 py-16 px-4">
        <div className="max-w-6xl mx-auto">
          <div className="grid md:grid-cols-4 gap-8 mb-12">
            <div>
              <div className="flex items-center space-x-2 mb-4">
                <div className="w-8 h-8 bg-blue-600 rounded-lg flex items-center justify-center">
                  <span className="text-white font-bold text-sm">AC</span>
                </div>
                <span className="text-lg font-bold text-white">ApexCardio</span>
              </div>
              <p className="text-sm leading-relaxed">Advanced cardiovascular health monitoring for everyone.</p>
            </div>
            <div>
              <h4 className="text-white font-semibold mb-4">Product</h4>
              <ul className="space-y-2 text-sm">
                <li><a href="/#features" className="hover:text-blue-400 transition">Features</a></li>
                <li><a href="/#download" className="hover:text-blue-400 transition">Download</a></li>
                <li><a href="/faq" className="hover:text-blue-400 transition">FAQ</a></li>
              </ul>
            </div>
            <div>
              <h4 className="text-white font-semibold mb-4">Company</h4>
              <ul className="space-y-2 text-sm">
                <li><a href="/about" className="hover:text-blue-400 transition">About Us</a></li>
                <li><a href="/#contact" className="hover:text-blue-400 transition">Contact</a></li>
                <li><a href="/blog" className="hover:text-blue-400 transition">Blog</a></li>
                <li><a href="/press" className="hover:text-blue-400 transition">Press</a></li>
              </ul>
            </div>
            <div>
              <h4 className="text-white font-semibold mb-4">Follow Us</h4>
              <div className="flex space-x-4">
                <a href="https://github.com" className="p-2 bg-gray-800 rounded-lg hover:bg-blue-600 transition" title="GitHub">
                  <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                    <path d="M12 2C6.477 2 2 6.477 2 12c0 4.42 2.865 8.17 6.839 9.49.5.092.682-.217.682-.482 0-.237-.008-.868-.013-1.703-2.782.603-3.369-1.343-3.369-1.343-.454-1.156-1.11-1.463-1.11-1.463-.908-.62.069-.608.069-.608 1.003.07 1.531 1.03 1.531 1.03.892 1.529 2.341 1.544 2.914 1.19.092-.926.35-1.545.636-1.9-2.22-.253-4.555-1.11-4.555-4.943 0-1.091.39-1.984 1.029-2.683-.103-.253-.446-1.27.098-2.647 0 0 .84-.269 2.75 1.025A9.578 9.578 0 0112 6.836c.85.004 1.705.114 2.504.336 1.909-1.294 2.747-1.025 2.747-1.025.546 1.377.203 2.394.1 2.647.64.699 1.028 1.592 1.028 2.683 0 3.842-2.339 4.687-4.566 4.935.359.309.678.919.678 1.852 0 1.336-.012 2.415-.012 2.743 0 .267.18.578.688.48C19.138 20.167 22 16.418 22 12c0-5.523-4.477-10-10-10z"/>
                  </svg>
                </a>
                <a href="https://instagram.com" className="p-2 bg-gray-800 rounded-lg hover:bg-blue-600 transition" title="Instagram">
                  <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                    <path d="M12 2.163c3.204 0 3.584.012 4.85.07 3.252.148 4.771 1.691 4.919 4.919.058 1.265.069 1.645.069 4.849 0 3.204-.012 3.584-.07 4.849-.149 3.225-1.664 4.771-4.919 4.919-1.266.058-1.644.07-4.85.07-3.204 0-3.584-.012-4.849-.07-3.26-.149-4.771-1.699-4.919-4.92-.058-1.265-.07-1.644-.07-4.849 0-3.204.013-3.583.07-4.849.149-3.227 1.664-4.771 4.919-4.919 1.266-.057 1.645-.069 4.849-.069zm0-2.163c-3.259 0-3.667.014-4.947.072-4.358.2-6.78 2.618-6.98 6.98-.059 1.281-.073 1.689-.073 4.948 0 3.259.014 3.668.072 4.948.2 4.358 2.618 6.78 6.98 6.98 1.281.058 1.689.072 4.948.072 3.259 0 3.668-.014 4.948-.072 4.354-.2 6.782-2.618 6.979-6.98.059-1.28.073-1.689.073-4.948 0-3.259-.014-3.667-.072-4.947-.196-4.354-2.617-6.78-6.979-6.98-1.281-.059-1.69-.073-4.949-.073zM5.838 12a6.162 6.162 0 1 1 12.324 0 6.162 6.162 0 0 1-12.324 0zM12 16a4 4 0 1 1 0-8 4 4 0 0 1 0 8zm4.965-10.322a1.44 1.44 0 1 1 2.881.001 1.44 1.44 0 0 1-2.881-.001z"/>
                  </svg>
                </a>
                <a href="https://tiktok.com" className="p-2 bg-gray-800 rounded-lg hover:bg-blue-600 transition" title="TikTok">
                  <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                    <path d="M19.59 6.69a4.83 4.83 0 0 1-3.77-4.25V2h-3.45v13.67a2.89 2.89 0 0 1-5.1 1.82 2.9 2.9 0 0 1 2.31-4.64 2.93 2.93 0 0 1 .88.135v-3.6a5.9 5.9 0 0 0-1-.1A6.56 6.56 0 0 0 5 13.75a6.47 6.47 0 0 0 10.61-5.3v-3.07a7.7 7.7 0 0 0 4.51 1.49v-3.4a4.6 4.6 0 0 1-.88-.08z"/>
                  </svg>
                </a>
                <a href="https://facebook.com" className="p-2 bg-gray-800 rounded-lg hover:bg-blue-600 transition" title="Facebook">
                  <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
                    <path d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z"/>
                  </svg>
                </a>
              </div>
            </div>
          </div>
          <div className="border-t border-gray-800 my-8"></div>
          <div className="flex flex-col md:flex-row justify-between items-center text-sm text-gray-400">
            <p>&copy; 2024 ApexCardio. All rights reserved.</p>
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
