// ============================================================
// supabase.js — Supabase client (loaded on every page)
// Replace the two constants below with your project values
// from: https://app.supabase.com → Project Settings → API
// ============================================================

const SUPABASE_URL  = 'https://okbkwqvksjswnifnarxt.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9rYmt3cXZrc2pzd25pZm5hcnh0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU0NDkwOTksImV4cCI6MjA5MTAyNTA5OX0.kIjesyyYwkBkk-7GeJz0x6AowH3FBtPPA4vEV6Z4m7M'

const { createClient } = supabase;
const _supabase = createClient(SUPABASE_URL, SUPABASE_ANON);

// ── Auth helpers ──────────────────────────────────────────────

async function getSession() {
  const { data: { session } } = await _supabase.auth.getSession();
  return session;
}

async function getCurrentUser() {
  const session = await getSession();
  return session ? session.user : null;
}

async function getCurrentProfile() {
  const user = await getCurrentUser();
  if (!user) return null;
  const { data } = await _supabase
    .from('profiles')
    .select('*')
    .eq('id', user.id)
    .single();
  return data;
}

async function isAdmin() {
  const profile = await getCurrentProfile();
  return profile?.role === 'admin';
}

// ── Guard: redirect to login if not authenticated ─────────────
async function requireAuth() {
  const user = await getCurrentUser();
  if (!user) {
    window.location.href = 'login.html';
  }
  return user;
}

// ── Guard: redirect away if not admin ─────────────────────────
async function requireAdmin() {
  const user  = await requireAuth();
  const admin = await isAdmin();
  if (!admin) {
    window.location.href = 'dashboard.html';
  }
  return user;
}

// ── Logout ────────────────────────────────────────────────────
async function logout() {
  await _supabase.auth.signOut();
  window.location.href = 'index.html';
}

// ── Avatar URL helper ─────────────────────────────────────────
function getAvatarUrl(path) {
  if (!path) return null;
  if (path.startsWith('http')) return path;
  const { data } = _supabase.storage.from('avatars').getPublicUrl(path);
  return data.publicUrl;
}

// ── Photo URL helper ──────────────────────────────────────────
function getPhotoUrl(path) {
  if (!path) return null;
  if (path.startsWith('http')) return path;
  const { data } = _supabase.storage.from('photos').getPublicUrl(path);
  return data.publicUrl;
}

// ── Navbar: inject logged-in user info ────────────────────────
async function initNavbar() {
  const profile = await getCurrentProfile();
  const navUser  = document.getElementById('nav-user');
  const navGuest = document.getElementById('nav-guest');
  const navName  = document.getElementById('nav-name');
  const navAvatar = document.getElementById('nav-avatar');
  const navAdmin = document.getElementById('nav-admin-link');

  if (profile) {
    if (navUser)  navUser.classList.remove('hidden');
    if (navGuest) navGuest.classList.add('hidden');
    if (navName)  navName.textContent = profile.full_name || '用户';
    if (navAvatar && profile.avatar_url) {
      navAvatar.src = getAvatarUrl(profile.avatar_url);
    }
    if (navAdmin) {
      navAdmin.style.display = profile.role === 'admin' ? 'flex' : 'none';
    }
  } else {
    if (navUser)  navUser.classList.add('hidden');
    if (navGuest) navGuest.classList.remove('hidden');
  }
}
