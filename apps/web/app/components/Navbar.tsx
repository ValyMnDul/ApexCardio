import Link from 'next/link';

export default function Navbar() {
  return (
    <nav className="sticky top-0 z-50 border-b border-gray-200 bg-white">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-4 sm:px-6 lg:px-8">
        <Link href="/" className="flex items-center space-x-2">
          <div className="flex h-8 w-8 items-center justify-center rounded-lg bg-blue-600">
            <span className="font-bold text-white">AC</span>
          </div>
          <span className="text-xl font-bold text-gray-900">ApexCardio</span>
        </Link>
        <div className="hidden space-x-8 md:flex">
          <Link href="/#features" className="text-gray-700 transition hover:text-blue-600">Features</Link>
          <Link href="/#download" className="text-gray-700 transition hover:text-blue-600">Download</Link>
          <Link href="/#contact" className="text-gray-700 transition hover:text-blue-600">Contact</Link>
        </div>
      </div>
    </nav>
  );
}