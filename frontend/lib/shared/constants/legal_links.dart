/// Canonical URLs for the public legal and support pages.
///
/// These are served from the same Firebase Hosting site as the Android
/// download page (backend/public/), and the same URLs are what App Store
/// Connect's Support URL / Privacy Policy URL fields point at — keeping the
/// in-app links and the store listing pointing at one place, so a page that
/// moves can't leave one of them dangling (App Review rejected a dead
/// Support URL once already, under guideline 1.5).
class LegalLinks {
  const LegalLinks._();

  static const String site = 'https://kvision-503115.web.app';
  static const String privacy = '$site/privacy.html';
  static const String terms = '$site/terms.html';
  static const String support = '$site/support.html';
}
