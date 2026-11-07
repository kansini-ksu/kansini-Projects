-- วางไฟล์นี้ใน Supabase → SQL Editor แล้วกด Run (ทำครั้งเดียว) — ตัวนับผู้เข้าชม

-- 1) ตารางเก็บยอดรายวัน (1 แถวต่อ 1 วัน)
create table if not exists public.site_visits (
  day    date primary key,
  visits bigint not null default 0
);

-- 2) เปิด RLS และ "ไม่สร้าง policy" = ใครก็อ่าน/เขียนตารางตรงๆ ไม่ได้ ต้องผ่านฟังก์ชันด้านล่างเท่านั้น
alter table public.site_visits enable row level security;

-- 3) ฟังก์ชันเพิ่มยอด (ถ้า p_increment = true) แล้วคืนค่า {today, total}
create or replace function public.hit_counter(p_increment boolean default true)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  d date := (now() at time zone 'Asia/Bangkok')::date;
  t bigint;
  a bigint;
begin
  if p_increment then
    insert into public.site_visits (day, visits) values (d, 1)
    on conflict (day) do update set visits = public.site_visits.visits + 1;
  end if;

  select coalesce(visits, 0) into t from public.site_visits where day = d;
  select coalesce(sum(visits), 0) into a from public.site_visits;

  return json_build_object('today', coalesce(t, 0), 'total', a);
end;
$$;

grant execute on function public.hit_counter(boolean) to anon, authenticated;
