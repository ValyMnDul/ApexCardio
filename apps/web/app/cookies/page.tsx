export default function Cookies() {
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
        </div>
      </nav>

      {/* Content */}
      <section className="py-20 px-4 bg-white">
        <div className="max-w-4xl mx-auto prose prose-lg max-w-none">
          <h1 className="text-5xl font-bold text-gray-900 mb-8">Cookie Policy</h1>
          
          <div className="space-y-8 text-gray-600 leading-relaxed">
            <div>
              <h2 className="text-2xl font-bold text-gray-900 mb-4">1. What Are Cookies?</h2>
              <p>
                Cookies are small pieces of data stored on your device that help us remember information about your visit. They are widely used to make websites work more efficiently and provide information to the owners of the site.
              </p>
            </div>

            <div>
              <h2 className="text-2xl font-bold text-gray-900 mb-4">2. How We Use Cookies</h2>
              <p>
                ApexCardio uses cookies to understand how you use our service, to remember your preferences, to improve your experience, and to analyze usage patterns. These cookies help us personalize your experience and provide better service.
              </p>
            </div>

            <div>
              <h2 className="text-2xl font-bold text-gray-900 mb-4">3. Types of Cookies We Use</h2>
              <p>
                We use session cookies (which expire when you close your browser) and persistent cookies (which remain on your device). We may also use cookies from third-party services to analyze traffic and user behavior.
              </p>
            </div>

            <div>
              <h2 className="text-2xl font-bold text-gray-900 mb-4">4. Managing Cookies</h2>
              <p>
                Most web browsers allow you to control cookies through their settings. You can choose to accept or reject cookies, or be notified when a cookie is being sent. However, blocking cookies may affect the functionality of our Service.
              </p>
            </div>

            <div>
              <h2 className="text-2xl font-bold text-gray-900 mb-4">5. Third-Party Cookies</h2>
              <p>
                Some cookies may be placed by third-party service providers who perform services on our behalf. We do not control these cookies and recommend reviewing their privacy policies to understand their practices.
              </p>
            </div>

            <div>
              <h2 className="text-2xl font-bold text-gray-900 mb-4">6. Contact Us</h2>
              <p>
                If you have questions about our cookie practices, please contact us at privacy@apexcardio.com.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="bg-gray-900 text-gray-300 py-16 px-4">
        <div className="max-w-6xl mx-auto">
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
