/**
 * Auth Bundle
 *
 * Loaded on authentication pages (/auth/*).
 */

import { initializeBundle } from "./bundle_utils"
import { PasswordToggle } from "../password_toggle"
import { AuthAutoFocus } from "../utility_hooks"

// Define auth-specific hooks
// (RecaptchaV3 is already registered in CoreHooks and inherited via initializeBundle)
const AuthHooks = {
  PasswordToggle,
  AuthAutoFocus
};

// Initialize bundle with shared utility (handles retry logic, errors, telemetry)
initializeBundle("auth", AuthHooks).catch(error => {
  console.error("Auth bundle initialization failed:", error);
});

export { PasswordToggle };
