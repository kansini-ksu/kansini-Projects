-- วางทั้งไฟล์นี้ใน Supabase → SQL Editor แล้วกด Run
-- ใช้กับหน้า decision1.html (ตัดสินใจ บทที่ 1: 3 ตัวเลือก ถูก 1 ผิด 2)
-- รันซ้ำได้ ไม่ทำให้ข้อมูลเดิมเสีย และใช้อัปเกรดจากเวอร์ชัน 4 ตัวเลือกได้ด้วย

-- 1) ตารางเฉลยของแต่ละตัวเลือก (หน้าเว็บอ่านตรงๆ ไม่ได้ เพราะเปิด RLS แล้วไม่ใส่ policy)
create table if not exists public.decision_options (
  scenario    text    not null,
  choice      int     not null check (choice between 0 and 3),   -- 0=ก, 1=ข, 2=ค
  points      int     not null default 0,                        -- คะแนนที่ได้ถ้าเลือกข้อนี้ (ข้อถูกใส่คะแนน ข้อผิดใส่ 0)
  is_correct  boolean not null default false,
  feedback    text    not null default '',                       -- เหตุผลที่แสดงในป๊อปอัป
  primary key (scenario, choice)
);
alter table public.decision_options add column if not exists is_correct boolean not null default false;
alter table public.decision_options enable row level security;

-- 2) ตารางผลสำเร็จของนักเรียน (บันทึกเมื่อ "ตอบถูก" เท่านั้น — 1 คนต่อ 1 สถานการณ์)
create table if not exists public.decision_results (
  user_id    uuid not null references auth.users(id) on delete cascade,
  scenario   text not null,
  choice     int  not null,
  score      int  not null,
  max_score  int  not null,
  feedback   text not null default '',
  attempts   int  not null default 1,                            -- ตอบกี่ครั้งกว่าจะถูก
  created_at timestamptz not null default now(),
  primary key (user_id, scenario)
);
alter table public.decision_results add column if not exists attempts int not null default 1;
alter table public.decision_results enable row level security;

drop policy if exists "read own decision" on public.decision_results;
create policy "read own decision"
  on public.decision_results for select
  using (auth.uid() = user_id);

-- 3) ตารางบันทึกทุกครั้งที่ตอบ (ทั้งถูกและผิด) ไว้ให้ครูดูว่านักเรียนพลาดข้อไหน
create table if not exists public.decision_attempts (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references auth.users(id) on delete cascade,
  scenario   text not null,
  choice     int  not null,
  is_correct boolean not null,
  created_at timestamptz not null default now()
);
alter table public.decision_attempts enable row level security;

drop policy if exists "read own attempts" on public.decision_attempts;
create policy "read own attempts"
  on public.decision_attempts for select
  using (auth.uid() = user_id);
-- ไม่มี policy insert/update ในทุกตาราง: นักเรียนเขียนตรงๆ ไม่ได้ ต้องผ่านฟังก์ชัน submit_decision เท่านั้น

-- 4) ★ ใส่เฉลยและเหตุผล (ตัวอย่าง — แก้ให้ตรงกับสถานการณ์จริง)
--    scenario 'l1' ต้องตรงกับ DECISION_ID ใน decision1.html
--    choice 0=ก, 1=ข, 2=ค (ลำดับต้องตรงกับ CHOICES ในหน้าเว็บ)
--    ต้องมีข้อที่ is_correct = true เพียง 1 ข้อเท่านั้น
delete from public.decision_options where scenario = 'l1' and choice = 3;   -- ลบข้อ ง ของเวอร์ชันเก่า (ถ้ามี)

insert into public.decision_options (scenario, choice, points, is_correct, feedback) values
  ('l1', 0, 1, true,  'ตัวอย่าง: ข้อ ก ถูกต้อง เพราะ ... (แก้เหตุผลที่ถูกตรงนี้)'),
  ('l1', 1, 0, false, 'ตัวอย่าง: ข้อ ข ไม่เหมาะสม เพราะ ... (แก้เหตุผลที่ผิดตรงนี้)'),
  ('l1', 2, 0, false, 'ตัวอย่าง: ข้อ ค ไม่เหมาะสม เพราะ ... (แก้เหตุผลที่ผิดตรงนี้)')
on conflict (scenario, choice) do update
  set points = excluded.points, is_correct = excluded.is_correct, feedback = excluded.feedback;

-- กันไม่ให้มีข้อถูกมากกว่า 1 ข้อในสถานการณ์เดียวกัน
create unique index if not exists decision_one_correct
  on public.decision_options (scenario) where is_correct;

-- 5) ฟังก์ชันบันทึกการตอบ (ตรวจถูก/ผิดและคิดคะแนนฝั่งฐานข้อมูล นักเรียนแก้เองไม่ได้)
create or replace function public.submit_decision(p_scenario text, p_choice int)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid      uuid := auth.uid();
  v_opt      public.decision_options%rowtype;
  v_max      int;
  v_attempts int;
begin
  if v_uid is null then raise exception 'not_authenticated'; end if;

  -- ตอบถูกไปแล้ว ไม่ให้ตอบซ้ำ
  if exists (select 1 from public.decision_results where user_id = v_uid and scenario = p_scenario) then
    raise exception 'already_submitted';
  end if;

  select * into v_opt from public.decision_options where scenario = p_scenario and choice = p_choice;
  if not found then raise exception 'no_key'; end if;

  select points into v_max from public.decision_options where scenario = p_scenario and is_correct limit 1;
  if v_max is null then raise exception 'no_key'; end if;

  insert into public.decision_attempts (user_id, scenario, choice, is_correct)
  values (v_uid, p_scenario, p_choice, v_opt.is_correct);

  select count(*) into v_attempts from public.decision_attempts where user_id = v_uid and scenario = p_scenario;

  if v_opt.is_correct then
    begin
      insert into public.decision_results (user_id, scenario, choice, score, max_score, feedback, attempts)
      values (v_uid, p_scenario, p_choice, v_opt.points, v_max, v_opt.feedback, v_attempts);
    exception when unique_violation then
      raise exception 'already_submitted';
    end;
  end if;

  return json_build_object(
    'correct',  v_opt.is_correct,
    'choice',   p_choice,
    'score',    case when v_opt.is_correct then v_opt.points else 0 end,
    'max',      v_max,
    'feedback', v_opt.feedback,
    'attempts', v_attempts
  );
end;
$$;

revoke all on function public.submit_decision(text, int) from public;
grant execute on function public.submit_decision(text, int) to authenticated;
