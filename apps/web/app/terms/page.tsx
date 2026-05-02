import Navbar from '../components/Navbar';
import Footer from '../components/Footer';

export default function Terms() {
  const sections = [
    { id: 'acceptance', title: '1. Acceptance of Terms' },
    { id: 'use-license', title: '2. Use License' },
    { id: 'medical-disclaimer', title: '3. Medical Disclaimer' },
    { id: 'user-responsibilities', title: '4. User Responsibilities' },
    { id: 'intellectual-property', title: '5. Intellectual Property Rights' },
    { id: 'limitation-liability', title: '6. Limitation of Liability' },
    { id: 'indemnification', title: '7. Indemnification' },
    { id: 'modifications', title: '8. Modifications to Service' },
    { id: 'termination', title: '9. Termination' },
    { id: 'governing-law', title: '10. Governing Law' },
    { id: 'contact', title: '11. Contact Information' },
  ];

  return (
    <div className="min-h-screen bg-white">
      <Navbar />

      <section className="py-20 px-4 bg-linear-to-br from-blue-50 to-white">
        <div className="max-w-6xl mx-auto">
          <div className="mb-12">
            <h1 className="text-5xl md:text-6xl font-bold text-gray-900 mb-4">
              Terms of Service
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
              <div id="acceptance" className="scroll-mt-20">
                <h2 className="text-3xl font-bold text-gray-900 mb-4">1. Acceptance of Terms</h2>
                <p className="text-gray-600 leading-relaxed mb-4">
                  By accessing, downloading, and using the ApexCardio mobile application and website (&quot;Service&quot;), you acknowledge that you have read, understood, and agree to be bound by these Terms of Service (&quot;Terms&quot;). If you do not agree to these Terms, you must immediately discontinue use of the Service.
                </p>
                <p className="text-gray-600 leading-relaxed">
                  ApexCardio reserves the right to modify these Terms at any time. Your continued use of the Service following such modifications constitutes your acceptance of the updated Terms.
                </p>
              </div>

              <div id="use-license" className="scroll-mt-20">
                <h2 className="text-3xl font-bold text-gray-900 mb-4">2. Use License</h2>
                <p className="text-gray-600 leading-relaxed mb-4">
                  ApexCardio grants you a limited, non-exclusive, non-transferable license to download and use the Service for personal, non-commercial purposes only. This license does not include the right to:
                </p>
                <ul className="space-y-2 text-gray-600 list-disc list-inside mb-4">
                  <li>Modify or copy the materials</li>
                  <li>Use the materials for any commercial purpose</li>
                  <li>Attempt to reverse engineer, decompile, or disassemble the Service</li>
                  <li>Remove any proprietary notices or labels</li>
                  <li>Transfer the license to another party</li>
                </ul>
                <p className="text-gray-600 leading-relaxed">
                  Any unauthorized use of the Service terminates this license and may violate applicable laws.
                </p>
              </div>

              <div id="medical-disclaimer" className="scroll-mt-20">
                <h2 className="text-3xl font-bold text-gray-900 mb-4">3. Medical Disclaimer</h2>
                <p className="text-gray-600 leading-relaxed mb-4 bg-red-50 border border-red-200 rounded-lg p-4">
                  <span className="font-bold text-red-900">IMPORTANT:</span> ApexCardio is a health monitoring application and NOT a medical device. The information provided by ApexCardio should not be used as a substitute for professional medical advice, diagnosis, or treatment.
                </p>
                <ul className="space-y-3 text-gray-600">
                  <li className="flex items-start">
                    <span className="text-blue-600 font-bold mr-3">•</span>
                    <span>Always consult with a qualified healthcare provider before making health decisions</span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-blue-600 font-bold mr-3">•</span>
                    <span>ApexCardio data should not replace clinical diagnosis or treatment</span>
                  </li>
                  <li className="flex items-start">
                    <span className="text-blue-600 font-bold mr-3">•</span>
                    <span>In case of emergency, call emergency services immediately</span>
                  </li>
                </ul>
              </div>

              <div id="user-responsibilities" className="scroll-mt-20">
                <h2 className="text-3xl font-bold text-gray-900 mb-4">4. User Responsibilities</h2>
                <p className="text-gray-600 leading-relaxed mb-4">
                  You agree to use the Service in compliance with all applicable laws and regulations. You are responsible for:
                </p>
                <ul className="space-y-2 text-gray-600 list-disc list-inside">
                  <li>Maintaining the confidentiality of your account credentials</li>
                  <li>Maintaining accurate and current account information</li>
                  <li>All activities that occur under your account</li>
                  <li>Notifying us immediately of any unauthorized use</li>
                  <li>Using the Service in a lawful and ethical manner</li>
                </ul>
              </div>

              <div id="intellectual-property" className="scroll-mt-20">
                <h2 className="text-3xl font-bold text-gray-900 mb-4">5. Intellectual Property Rights</h2>
                <p className="text-gray-600 leading-relaxed">
                  All content, features, and functionality of the Service, including but not limited to text, graphics, logos, icons, images, audio clips, digital downloads, data compilations, and software, are the exclusive property of ApexCardio and are protected by international copyright, trademark, and other intellectual property laws.
                </p>
              </div>

              <div id="limitation-liability" className="scroll-mt-20">
                <h2 className="text-3xl font-bold text-gray-900 mb-4">6. Limitation of Liability</h2>
                <p className="text-gray-600 leading-relaxed mb-4">
                  TO THE MAXIMUM EXTENT PERMITTED BY LAW, APEXCARDIO SHALL NOT BE LIABLE FOR:
                </p>
                <ul className="space-y-2 text-gray-600 list-disc list-inside mb-4">
                  <li>Indirect, incidental, special, or consequential damages</li>
                  <li>Loss of profits, data, or use</li>
                  <li>Business interruption</li>
                  <li>Personal injury or property damage</li>
                </ul>
                <p className="text-gray-600 leading-relaxed">
                  The total liability of ApexCardio for any claims shall not exceed the amount paid by you for the Service.
                </p>
              </div>

              <div id="indemnification" className="scroll-mt-20">
                <h2 className="text-3xl font-bold text-gray-900 mb-4">7. Indemnification</h2>
                <p className="text-gray-600 leading-relaxed">
                  You agree to defend, indemnify, and hold harmless ApexCardio, its officers, directors, employees, and agents from any claims, damages, losses, or expenses (including attorney&apos;s fees) arising from your use of the Service, your violation of these Terms, or your violation of any rights of third parties.
                </p>
              </div>

              <div id="modifications" className="scroll-mt-20">
                <h2 className="text-3xl font-bold text-gray-900 mb-4">8. Modifications to Service</h2>
                <p className="text-gray-600 leading-relaxed">
                  ApexCardio reserves the right to modify, suspend, or discontinue the Service at any time with or without notice. We shall not be liable to you or any third party for any modification, suspension, or discontinuance of the Service.
                </p>
              </div>

              <div id="termination" className="scroll-mt-20">
                <h2 className="text-3xl font-bold text-gray-900 mb-4">9. Termination</h2>
                <p className="text-gray-600 leading-relaxed mb-4">
                  Your license to use the Service is personal and non-transferable. ApexCardio may terminate your account and access to the Service at any time for any reason, with or without notice. Upon termination:
                </p>
                <ul className="space-y-2 text-gray-600 list-disc list-inside">
                  <li>Your right to use the Service terminates immediately</li>
                  <li>You must cease all use of the Service</li>
                  <li>Your account data may be deleted after a reasonable retention period</li>
                </ul>
              </div>

              <div id="governing-law" className="scroll-mt-20">
                <h2 className="text-3xl font-bold text-gray-900 mb-4">10. Governing Law</h2>
                <p className="text-gray-600 leading-relaxed">
                  These Terms shall be governed by and construed in accordance with the laws of the State of California, without regard to its conflict of law principles. Any disputes arising from these Terms shall be subject to the exclusive jurisdiction of the state and federal courts located in California.
                </p>
              </div>

              <div id="contact" className="scroll-mt-20 bg-blue-50 rounded-lg p-8">
                <h2 className="text-3xl font-bold text-gray-900 mb-4">11. Contact Information</h2>
                <p className="text-gray-600 leading-relaxed mb-4">
                  If you have questions about these Terms of Service, please contact us:
                </p>
                <div className="space-y-3 text-gray-600">
                  <p>
                    <span className="font-semibold text-gray-900">Email:</span> support@apexcardio.com
                  </p>
                  <p>
                    <span className="font-semibold text-gray-900">Address:</span> ApexCardio, Inc., 123 Health Ave, San Francisco, CA 94105
                  </p>
                  <p>
                    <span className="font-semibold text-gray-900">Phone:</span> +1 (555) 123-4567
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