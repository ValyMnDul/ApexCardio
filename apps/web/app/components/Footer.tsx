import Link from 'next/link';
import { FaFacebook, FaGithub, FaInstagram } from 'react-icons/fa';
import { SiTiktok } from 'react-icons/si';

export default function Footer() {
  return (
    <footer className="bg-gray-900 px-4 py-16 text-gray-300">
      <div className="mx-auto max-w-6xl">
        <div className="grid gap-8 mb-12 md:grid-cols-4">
          <div>
            <div className="mb-4 flex items-center space-x-2">
              <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-blue-600">
                <span className="text-sm font-bold text-white">AC</span>
              </div>
              <span className="text-lg font-bold text-white">ApexCardio</span>
            </div>
            <p className="text-sm leading-relaxed">Advanced cardiovascular health monitoring for everyone.</p>
          </div>

          <div>
            <h4 className="mb-4 font-semibold text-white">Product</h4>
            <ul className="space-y-2 text-sm">
              <li><Link href="/#features" className="transition hover:text-blue-400">Features</Link></li>
              <li><Link href="/#download" className="transition hover:text-blue-400">Download</Link></li>
              <li><Link href="/faq" className="transition hover:text-blue-400">FAQ</Link></li>
            </ul>
          </div>

          <div>
            <h4 className="mb-4 font-semibold text-white">Company</h4>
            <ul className="space-y-2 text-sm">
              <li><Link href="/about" className="transition hover:text-blue-400">About Us</Link></li>
              <li><Link href="/#contact" className="transition hover:text-blue-400">Contact</Link></li>
            </ul>
          </div>

          <div>
            <h4 className="mb-4 font-semibold text-white">Follow Us</h4>
            <div className="flex space-x-4">
              <a href="https://github.com" className="flex items-center justify-center rounded-lg bg-gray-800 p-2 text-white transition hover:bg-blue-600" title="GitHub" aria-label="GitHub"><FaGithub className="h-5 w-5" aria-hidden="true" /></a>
              <a href="https://instagram.com" className="flex items-center justify-center rounded-lg bg-gray-800 p-2 text-white transition hover:bg-pink-500" title="Instagram" aria-label="Instagram"><FaInstagram className="h-5 w-5" aria-hidden="true" /></a>
              <a href="https://tiktok.com" className="flex items-center justify-center rounded-lg bg-gray-800 p-2 text-white transition hover:bg-black" title="TikTok" aria-label="TikTok"><SiTiktok className="h-5 w-5" aria-hidden="true" /></a>
              <a href="https://facebook.com" className="flex items-center justify-center rounded-lg bg-gray-800 p-2 text-white transition hover:bg-blue-700" title="Facebook" aria-label="Facebook"><FaFacebook className="h-5 w-5" aria-hidden="true" /></a>
            </div>
          </div>
        </div>

        <div className="my-8 border-t border-gray-800"></div>

        <div className="flex flex-col items-center justify-between text-sm text-gray-400 md:flex-row">
          <p>&copy; 2026 ApexCardio. All rights reserved.</p>
          <div className="mt-4 flex space-x-6 md:mt-0">
            <Link href="/privacy" className="transition hover:text-blue-400">Privacy Policy</Link>
            <Link href="/terms" className="transition hover:text-blue-400">Terms of Service</Link>
          </div>
        </div>
      </div>
    </footer>
  );
}