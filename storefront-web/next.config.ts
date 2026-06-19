import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  output: "export",
  distDir: "dist",
  trailingSlash: true,
  assetPrefix: "/storefront",
};

export default nextConfig;
