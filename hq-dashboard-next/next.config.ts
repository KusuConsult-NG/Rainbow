import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // output: 'export' removed — static export is incompatible with Next.js middleware
  // (auth guard). The HQ dashboard is served via Firebase App Hosting (Node.js runtime)
  // which supports SSR and edge middleware for RBAC enforcement (PRD §4).
  images: {
    unoptimized: true,
  },
};

export default nextConfig;
