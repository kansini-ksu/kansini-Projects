-- วางใน Supabase → SQL Editor แล้วกด Run (ทำครั้งเดียว)
-- คัดลอกเฉลยของ pretest ไปเป็นเฉลยของ posttest (ใช้เมื่อข้อสอบหลังเรียนเป็นชุดเดียวกับก่อนเรียน ลำดับข้อและตัวเลือกเหมือนเดิม)
insert into public.quiz_keys (quiz, q_no, correct, points)
select 'posttest', q_no, correct, points
from public.quiz_keys
where quiz = 'pretest'
on conflict (quiz, q_no) do nothing;

-- ตรวจผล: ต้องเห็น 10 แถวของ posttest
select * from public.quiz_keys where quiz = 'posttest' order by q_no;
