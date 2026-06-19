import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  // Override default ignores of eslint-config-next.
  globalIgnores([
    // Default ignores of eslint-config-next:
    ".next/**",
    "out/**",
    "build/**",
    "dist/**",
    "next-env.d.ts",
  ]),
  {
    rules: {
      // Loading bootstrap data on mount and setting state is a standard SPA pattern.
      "react-hooks/set-state-in-effect": "off",
      // Product/service images come from external business URLs.
      "@next/next/no-img-element": "off",
    },
  },
]);

export default eslintConfig;
