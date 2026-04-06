-- ============================================================
-- FAMILY TREE WEBSITE — SUPABASE DATABASE SETUP
-- Run this entire file in Supabase SQL Editor
-- ============================================================

-- ── 1. PROFILES ─────────────────────────────────────────────
-- Extends Supabase auth.users with personal info
CREATE TABLE profiles (
  id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name     TEXT,
  nationality   TEXT,
  date_of_birth DATE,
  phone         TEXT,
  hometown      TEXT,
  occupation    TEXT,
  bio           TEXT,
  avatar_url    TEXT,
  role          TEXT NOT NULL DEFAULT 'member',  -- 'admin' | 'member'
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ── 2. FAMILY MEMBERS ───────────────────────────────────────
-- Each node in the family tree (may or may not have an account)
CREATE TABLE family_members (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT NOT NULL,
  gender        TEXT,                             -- 'male' | 'female' | 'other'
  date_of_birth DATE,
  date_of_death DATE,
  nationality   TEXT,
  hometown      TEXT,
  occupation    TEXT,
  bio           TEXT,
  avatar_url    TEXT,
  profile_id    UUID REFERENCES profiles(id),     -- linked account (optional)
  created_by    UUID REFERENCES profiles(id),
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ── 3. RELATIONSHIPS ────────────────────────────────────────
-- Links between family members
-- relationship_type: 'parent_child' | 'spouse' | 'sibling'
CREATE TABLE relationships (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  member_a_id       UUID NOT NULL REFERENCES family_members(id) ON DELETE CASCADE,
  member_b_id       UUID NOT NULL REFERENCES family_members(id) ON DELETE CASCADE,
  relationship_type TEXT NOT NULL,
  created_by        UUID REFERENCES profiles(id),
  created_at        TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT no_self_relation CHECK (member_a_id <> member_b_id)
);

-- ── 4. PHOTOS ───────────────────────────────────────────────
CREATE TABLE photos (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  storage_path  TEXT NOT NULL,                    -- Supabase Storage path
  caption       TEXT,
  uploaded_by   UUID REFERENCES profiles(id),
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- ── 5. PHOTO TAGS ───────────────────────────────────────────
-- Which family members appear in a photo
CREATE TABLE photo_tags (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  photo_id    UUID NOT NULL REFERENCES photos(id) ON DELETE CASCADE,
  member_id   UUID NOT NULL REFERENCES family_members(id) ON DELETE CASCADE,
  UNIQUE(photo_id, member_id)
);

-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================

ALTER TABLE profiles       ENABLE ROW LEVEL SECURITY;
ALTER TABLE family_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE relationships  ENABLE ROW LEVEL SECURITY;
ALTER TABLE photos         ENABLE ROW LEVEL SECURITY;
ALTER TABLE photo_tags     ENABLE ROW LEVEL SECURITY;

-- Profiles: users can read all, but only edit their own
CREATE POLICY "Public profiles are viewable by logged-in users"
  ON profiles FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Users can update own profile"
  ON profiles FOR UPDATE
  USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile"
  ON profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

-- Family members: all logged-in users can read; only admins can insert/update/delete
CREATE POLICY "Logged-in users can view family members"
  ON family_members FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Admins can insert family members"
  ON family_members FOR INSERT
  WITH CHECK (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "Admins can update family members"
  ON family_members FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "Admins can delete family members"
  ON family_members FOR DELETE
  USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- Relationships: same pattern as family members
CREATE POLICY "Logged-in users can view relationships"
  ON relationships FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Admins can manage relationships"
  ON relationships FOR ALL
  USING (
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- Photos: all logged-in users can view and upload; only admins or uploader can delete
CREATE POLICY "Logged-in users can view photos"
  ON photos FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Logged-in users can upload photos"
  ON photos FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "Uploader or admin can delete photos"
  ON photos FOR DELETE
  USING (
    uploaded_by = auth.uid() OR
    EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
  );

-- Photo tags
CREATE POLICY "Logged-in users can view photo tags"
  ON photo_tags FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "Logged-in users can tag photos"
  ON photo_tags FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

-- ============================================================
-- AUTO-CREATE PROFILE ON SIGNUP
-- First user ever registered becomes admin, rest become member
-- ============================================================
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  user_count INT;
  assigned_role TEXT;
BEGIN
  SELECT COUNT(*) INTO user_count FROM profiles;
  IF user_count = 0 THEN
    assigned_role := 'admin';
  ELSE
    assigned_role := 'member';
  END IF;

  INSERT INTO profiles (id, full_name, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    assigned_role
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ============================================================
-- STORAGE BUCKET FOR PHOTOS & AVATARS
-- Run separately in Supabase Storage UI or via this SQL
-- ============================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('photos', 'photos', true)
ON CONFLICT DO NOTHING;

-- Storage policies
CREATE POLICY "Anyone logged in can upload avatars"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'avatars' AND auth.role() = 'authenticated');

CREATE POLICY "Avatars are publicly readable"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

CREATE POLICY "Anyone logged in can upload photos"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'photos' AND auth.role() = 'authenticated');

CREATE POLICY "Photos are publicly readable"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'photos');
