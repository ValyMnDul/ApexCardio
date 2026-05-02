import Navbar from '../components/Navbar';
import Footer from '../components/Footer';

export default function Privacy() {
  const sections = [
    { id: 'introduction', title: '1. Introduction' },
    { id: 'information-collection', title: '2. Information We Collect' },
    { id: 'information-use', title: '3. How We Use Your Information' },
    { id: 'data-security', title: '4. Data Security' },
    { id: 'your-rights', title: '5. Your Rights' },
    { id: 'third-parties', title: '6. Third-Party Services' },
    { id: 'children', title: '7. Children\'s Privacy' },
    { id: 'changes', title: '8. Changes to Privacy Policy' },
    { id: 'contact', title: '9. Contact Us' },
  ];

  return (
    <div className="min-h-screen bg-white">
      <Navbar />

      <section className="py-20 px-4 bg-linear-to-br from-blue-50 to-white">
        <div className="max-w-6xl mx-auto">
          <div className="mb-12">
            <h1 className="text-5xl md:text-6xl font-bold text-gray-900 mb-4">
              Privacy Policy
            </h1>
            <p className="text-xl text-gray-600">
              Last updated: May 2, 2026
            </p>
          </div>

          <div className="grid md:grid-cols-4 gap-8">
            {/* Table of Contents */}
            <div className="md:col-span-1">
              <div className="sticky top-24 bg-white rounded-lg border border-gray-200 p-6 shadow-sm">
                <h3 className="text-lg font-bold text-gray-900 mb-4">Contents</h3>
                <nav className="space-y-2">
                  {sections.map((section) => (
                    <a
                      key={section.id}
                      href={`#${section.id}`}
                      className="block text-sm text-gray-600 hover:text-blue-600 transition"
                    >
                      {section.title}
                    </a>
                  ))}
                </nav>
              </div>
            </div>

            {/* Main Content */}
            <div className="md:col-span-3 space-y-12">
              <div id="introduction" className="scroll-mt-20">
                <h2 className="text-3xl font-bold text-gray-900 mb-4">1. Introduction</h2>
                <p className="text-gray-600 leading-relaxed mb-4">
                  ApexCardio (&quot;we,&quot; &quot;us,&quot; &quot;our,&quot; or &quot;Company&quot;) is committed to protecting your privacy and ensuring you have a positive experience on our mobile application and website. This Privacy Policy explains how we collect, use, disclose, and otherwise handle your personal information in connection with our services.
                </p>
                <p className="text-gray-600 leading-relaxed">
                  We take your privacy seriously and comply with applicable data protection laws, including the General Data Protection Regulation (GDPR) and the California Consumer Privacy Act (CCPA).
                </p>
              </div>

              <div id="information-collection" className="scroll-mt-20">
                <h2 className="text-3xl font-bold text-gray-900 mb-4">2. Information We Collect</h2>
                <div className="space-y-6">
                  <div>
                    <h3 className="text-lg font-semibold text-gray-900 mb-2">Information You Provide</h3>
                    <ul className="list-disc list-inside space-y-2 text-gray-600">
                      <li>Account information (name, email, phone number)</li>
                      <li>Health and fitness data (heart rate, exercise data, goals)</li>
                      <li>Demographic information (age, gender, weight, height)</li>
                      <li>Communication preferences and feedback</li>
                    </ul>
                  </div>
                  <div>
                    <h3 className="text-lg font-semibold text-gray-900 mb-2">Automatically Collected Information</h3>
                    <ul className="list-disc list-inside space-y-2 text-gray-600">
                      <li>Device information (type, model, operating system)</li>
                      <li>Usage patterns and analytics</li>
                      <li>IP address and location data</li>
                      <li>Cookies and similar tracking technologies</li>
                    </ul>
                  </div>
                </div>
              </div>

              <div id="information-use" className="scroll-mt-20">
                <h2 className="text-3xl font-bold text-gray-900 mb-4">3. How We Use Your Information</h2>
                <p className="text-gray-600 leading-relaxed mb-4">
                  We use the information we collect for the following purposes:
                </p>
                <ul className="space-y-3 text-gray-600">
                  <li className="flex items-start">
                    <span className="text-blue-600 font-bold mr-3">•</span>
                    <span>Provide and improve our services</span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-blue-600 font-bold mr-3">•</span>
                    <span>Personalize your experience and provide recommendations</span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-blue-600 font-bold mr-3">•</span>
                    <span>Send technical notices, security alerts, and support messages</span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-blue-600 font-bold mr-3">•</span>
                    <span>Respond to your inquiries and provide customer support</span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-blue-600 font-bold mr-3">•</span>
                    <span>Send marketing communications (only with your consent)</span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-blue-600 font-bold mr-3">•</span>
                    <span>Analyze usage trends and conduct research</span>
                  </li>
                </ul>
              </div>

              <div id="data-security" className="scroll-mt-20">
                <h2 className="text-3xl font-bold text-gray-900 mb-4">4. Data Security</h2>
                <p className="text-gray-600 leading-relaxed mb-4">
                  We implement comprehensive technical and organizational measures to protect your personal information against unauthorized access, alteration, disclosure, or destruction. Our security measures include:
                </p>
                <ul className="space-y-2 text-gray-600 list-disc list-inside">
                  <li>End-to-end encryption for sensitive data</li>
                  <li>Secure SSL/TLS connections</li>
                  <li>Regular security audits and penetration testing</li>
                  <li>Restricted access to personal information</li>
                  <li>Employee training on data protection</li>
                </ul>
                <p className="text-gray-600 leading-relaxed mt-4">
                  However, no method of transmission over the internet is 100% secure. While we strive to protect your information, we cannot guarantee absolute security.
                </p>
              </div>

              <div id="your-rights" className="scroll-mt-20">
                <h2 className="text-3xl font-bold text-gray-900 mb-4">5. Your Rights</h2>
                <p className="text-gray-600 leading-relaxed mb-4">
                  You have the following rights regarding your personal information:
                </p>
                <ul className="space-y-3 text-gray-600">
                  <li><span className="font-semibold text-gray-900">Access:</span> Request access to your personal information</li>
                  <li><span className="font-semibold text-gray-900">Correction:</span> Correct inaccurate or incomplete information</li>
                  <li><span className="font-semibold text-gray-900">Deletion:</span> Request deletion of your data</li>
                  <li><span className="font-semibold text-gray-900">Opt-out:</span> Unsubscribe from marketing communications</li>
                  <li><span className="font-semibold text-gray-900">Portability:</span> Receive your data in a portable format</li>
                </ul>
              </div>

              <div id="third-parties" className="scroll-mt-20">
                <h2 className="text-3xl font-bold text-gray-900 mb-4">6. Third-Party Services</h2>
                <p className="text-gray-600 leading-relaxed">
                  We may share your information with third-party service providers who assist us in operating our website and conducting our business, subject to confidentiality agreements. We do not sell or rent your personal information to third parties. Third-party services may have their own privacy policies, and we encourage you to review them.
                </p>
              </div>

              <div id="children" className="scroll-mt-20">
                <h2 className="text-3xl font-bold text-gray-900 mb-4">7. Children&apos;s Privacy</h2>
                <p className="text-gray-600 leading-relaxed">
                  Our services are not designed for children under 13 years old. We do not knowingly collect personal information from children under 13. If we become aware that we have collected information from a child under 13, we will take steps to delete such information and terminate the child&apos;s account.
                </p>
              </div>

              <div id="changes" className="scroll-mt-20">
                <h2 className="text-3xl font-bold text-gray-900 mb-4">8. Changes to Privacy Policy</h2>
                <p className="text-gray-600 leading-relaxed">
                  We may update this Privacy Policy from time to time. Any changes will be posted on this page with an updated &quot;Last Updated&quot; date. Your continued use of our services following the posting of changes constitutes your acceptance of such changes.
                </p>
              </div>

              <div id="contact" className="scroll-mt-20 bg-blue-50 rounded-lg p-8">
                <h2 className="text-3xl font-bold text-gray-900 mb-4">9. Contact Us</h2>
                <p className="text-gray-600 leading-relaxed mb-4">
                  If you have questions about this Privacy Policy or our privacy practices, please contact us:
                </p>
                <div className="space-y-3 text-gray-600">
                  <p>
                    <span className="font-semibold text-gray-900">Email:</span> privacy@apexcardio.com
                  </p>
                  <p>
                    <span className="font-semibold text-gray-900">Address:</span> ApexCardio, Inc., 123 Health Ave, San Francisco, CA 94105
                  </p>
                  <p>
                    <span className="font-semibold text-gray-900">Response Time:</span> We typically respond to requests within 30 days.
                  </p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <Footer />
    </div>
  );
}
