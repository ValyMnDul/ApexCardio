import Navbar from '../components/Navbar';
import Footer from '../components/Footer';
export default function Privacy() {
  return (
    <div className="min-h-screen bg-white">
      <Navbar />

      {/* Content */}
      <section className="py-20 px-4 bg-white">
        <div className="mx-auto prose prose-lg max-w-none">
          <h1 className="text-5xl font-bold text-gray-900 mb-8">Privacy Policy</h1>
          
          <div className="space-y-8 text-gray-600 leading-relaxed">
            <div>
              <h2 className="text-2xl font-bold text-gray-900 mb-4">1. Introduction</h2>
              <p>
                ApexCardio (&quot;we,&quot; &quot;us,&quot; &quot;our,&quot; or &quot;Company&quot;) is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and otherwise handle your information when you use our mobile application and website.
              </p>
            </div>

            <div>
              <h2 className="text-2xl font-bold text-gray-900 mb-4">2. Information We Collect</h2>
              <p>
                We collect information you provide directly, such as when you create an account, including your name, email address, and health data. We also automatically collect certain information about your device and how you interact with our services, including IP address, device type, and usage patterns.
              </p>
            </div>

            <div>
              <h2 className="text-2xl font-bold text-gray-900 mb-4">3. How We Use Your Information</h2>
              <p>
                We use your information to provide, maintain, and improve our services; to send you technical notices and support messages; to respond to your comments and questions; and to send you marketing communications (with your consent). Health data is used solely for providing our health monitoring services.
              </p>
            </div>

            <div>
              <h2 className="text-2xl font-bold text-gray-900 mb-4">4. Data Security</h2>
              <p>
                We implement appropriate technical and organizational measures to protect your personal information against unauthorized access, alteration, disclosure, or destruction. However, no method of transmission over the internet is 100% secure.
              </p>
            </div>

            <div>
              <h2 className="text-2xl font-bold text-gray-900 mb-4">5. Your Rights</h2>
              <p>
                You have the right to access, correct, update, or delete your personal information. You may also opt-out of receiving marketing communications by following the instructions in those messages or by contacting us directly.
              </p>
            </div>

            <div>
              <h2 className="text-2xl font-bold text-gray-900 mb-4">6. Contact Us</h2>
              <p>
                If you have questions about this Privacy Policy or our privacy practices, please contact us at privacy@apexcardio.com.
              </p>
            </div>
          </div>
        </div>
      </section>

      <Footer />
    </div>
  );
}
