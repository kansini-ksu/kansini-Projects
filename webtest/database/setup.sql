-- วางทั้งไฟล์นี้ใน Supabase → SQL Editor แล้วกด Run (ทำครั้งเดียว)

-- 1) ตารางเก็บข้อมูลโปรไฟล์ผู้ใช้ (รหัสผ่านถูกเก็บแบบเข้ารหัสใน auth.users โดย Supabase อยู่แล้ว)
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  username    text unique not null check (username ~ '^[a-z0-9_]{4,20}$'),
  full_name   text not null,
  created_at  timestamptz not null default now()
);

-- 2) เปิด Row Level Security: ผู้ใช้เห็น/แก้ได้เฉพาะข้อมูลของตัวเอง
alter table public.profiles enable row level security;

drop policy if exists "read own profile"   on public.profiles;
drop policy if exists "update own profile" on public.profiles;

create policy "read own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "update own profile"
  on public.profiles for update
  using (auth.uid() = id);

-- 3) สร้างแถวใน profiles อัตโนมัติทุกครั้งที่มีคนสมัคร
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, username, full_name)
  values (
    new.id,
    new.raw_user_meta_data ->> 'username',
    coalesce(new.raw_user_meta_data ->> 'full_name', '')
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
