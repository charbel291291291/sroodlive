-- ────────────────────────────────────────────────────────────────────────────
-- Gold Ladder Quiz — original trivia mini game for Srood Live
--   12 questions per run, entry fee 100/500/1000 coins, safe points at Q5/Q10.
--   Correct answers NEVER leave the server until the player has answered.
--   All coin logic lives in SQL — the WebView only animates results.
-- ────────────────────────────────────────────────────────────────────────────

-- ── 1. gold_ladder_questions ─────────────────────────────────────────────────

create table if not exists public.gold_ladder_questions (
  id           uuid primary key default gen_random_uuid(),
  text         text not null,
  text_ar      text not null,
  option_a     text not null,
  option_b     text not null,
  option_c     text not null,
  option_d     text not null,
  option_a_ar  text not null,
  option_b_ar  text not null,
  option_c_ar  text not null,
  option_d_ar  text not null,
  correct_option char(1) not null check (correct_option in ('a','b','c','d')),
  explanation  text,
  difficulty   text not null default 'medium'
                 check (difficulty in ('easy','medium','hard')),
  category     text,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now()
);

alter table public.gold_ladder_questions enable row level security;

drop policy if exists "gold_ladder_questions_select" on public.gold_ladder_questions;
create policy "gold_ladder_questions_select"
  on public.gold_ladder_questions for select to authenticated
  using (false); -- never exposed directly; only via RPCs that strip correct_option

grant select on public.gold_ladder_questions to authenticated;

-- ── 2. gold_ladder_runs ──────────────────────────────────────────────────────

create table if not exists public.gold_ladder_runs (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid not null references auth.users(id) on delete cascade,
  entry_fee             integer not null check (entry_fee in (100, 500, 1000)),
  status                text not null default 'active'
                          check (status in ('active','completed','eliminated','cashed_out')),
  current_question_num  integer not null default 1 check (current_question_num between 1 and 13),
  highest_safe_question integer not null default 0 check (highest_safe_question in (0,5,10)),
  cashout_amount        integer not null default 0,
  powers_remaining      jsonb not null default '{"remove_two":1,"crowd_pulse":1,"second_chance":1}'::jsonb,
  second_chance_active  boolean not null default false,
  question_ids          uuid[] not null,
  created_at            timestamptz not null default now()
);

alter table public.gold_ladder_runs enable row level security;

drop policy if exists "gold_ladder_runs_own" on public.gold_ladder_runs;
create policy "gold_ladder_runs_own"
  on public.gold_ladder_runs for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

grant select on public.gold_ladder_runs to authenticated;

-- ── 3. gold_ladder_answers ───────────────────────────────────────────────────

create table if not exists public.gold_ladder_answers (
  id              uuid primary key default gen_random_uuid(),
  run_id          uuid not null references public.gold_ladder_runs(id) on delete cascade,
  question_id     uuid not null references public.gold_ladder_questions(id),
  question_number integer not null,
  selected_option char(1) not null check (selected_option in ('a','b','c','d')),
  is_correct      boolean not null,
  answered_at     timestamptz not null default now()
);

alter table public.gold_ladder_answers enable row level security;

drop policy if exists "gold_ladder_answers_own" on public.gold_ladder_answers;
create policy "gold_ladder_answers_own"
  on public.gold_ladder_answers for all to authenticated
  using (
    exists (
      select 1 from public.gold_ladder_runs r
      where r.id = run_id and r.user_id = auth.uid()
    )
  );

grant select on public.gold_ladder_answers to authenticated;

-- ── 4. game_settings entry ───────────────────────────────────────────────────

insert into public.game_settings (game_key, is_enabled)
values ('gold_ladder', true)
on conflict (game_key) do nothing;

-- ── 5. Extend wallet_transactions type constraint ────────────────────────────

alter table public.wallet_transactions
drop constraint if exists wallet_transactions_type_check;

alter table public.wallet_transactions
add constraint wallet_transactions_type_check check (
  type in (
    'recharge_request',
    'admin_adjustment',
    'gift_sent',
    'gift_received',
    'agency_recharge',
    'refund',
    'system',
    'withdrawal',
    'withdrawal_refund',
    'agency_commission',
    'hungry_cat_bet',
    'hungry_cat_reward',
    'hungry_cat_refund',
    'gold_ladder_entry',
    'gold_ladder_win',
    'gold_ladder_safe_payout'
  )
);

-- ── 6. Seed questions (bilingual EN + AR) ────────────────────────────────────
-- 15 easy + 10 medium + 10 hard = 35 bilingual questions

insert into public.gold_ladder_questions
  (text, text_ar, option_a, option_b, option_c, option_d,
   option_a_ar, option_b_ar, option_c_ar, option_d_ar,
   correct_option, explanation, difficulty, category)
values
-- ── EASY ────────────────────────────────────────────────────────────────────
(
  'What is the capital of France?',
  'ما هي عاصمة فرنسا؟',
  'Berlin', 'Paris', 'Madrid', 'Rome',
  'برلين', 'باريس', 'مدريد', 'روما',
  'b', 'Paris has been the capital of France since 987 AD.', 'easy', 'geography'
),
(
  'How many colors are in a rainbow?',
  'كم عدد ألوان قوس قزح؟',
  '5', '7', '8', '6',
  '٥', '٧', '٨', '٦',
  'b', 'A rainbow has 7 colors: red, orange, yellow, green, blue, indigo, violet.', 'easy', 'science'
),
(
  'Which planet is closest to the Sun?',
  'أي كوكب هو الأقرب من الشمس؟',
  'Venus', 'Earth', 'Mercury', 'Mars',
  'الزهرة', 'الأرض', 'عطارد', 'المريخ',
  'c', 'Mercury is the closest planet to the Sun in our solar system.', 'easy', 'science'
),
(
  'What is 15 + 27?',
  'كم يساوي 15 + 27؟',
  '40', '43', '41', '42',
  '٤٠', '٤٣', '٤١', '٤٢',
  'd', '15 + 27 = 42.', 'easy', 'math'
),
(
  'Which ocean is the largest?',
  'أي المحيطات هو الأكبر؟',
  'Pacific', 'Atlantic', 'Indian', 'Arctic',
  'المحيط الهادئ', 'المحيط الأطلسي', 'المحيط الهندي', 'المحيط المتجمد الشمالي',
  'a', 'The Pacific Ocean covers more than 30% of Earth''s surface.', 'easy', 'geography'
),
(
  'What animal is known as "man''s best friend"?',
  'ما الحيوان الذي يُعرف بـ"أفضل صديق للإنسان"؟',
  'Cat', 'Dog', 'Horse', 'Rabbit',
  'القطة', 'الكلب', 'الحصان', 'الأرنب',
  'b', 'Dogs have been loyal companions to humans for thousands of years.', 'easy', 'general'
),
(
  'How many days are in a leap year?',
  'كم عدد أيام السنة الكبيسة؟',
  '364', '365', '366', '367',
  '٣٦٤', '٣٦٥', '٣٦٦', '٣٦٧',
  'c', 'A leap year has 366 days, with February having 29 days instead of 28.', 'easy', 'general'
),
(
  'What is the boiling point of water in Celsius?',
  'ما هي درجة غليان الماء بالمئوية؟',
  '90°C', '100°C', '110°C', '80°C',
  '٩٠°م', '١٠٠°م', '١١٠°م', '٨٠°م',
  'b', 'Water boils at 100°C (212°F) at standard atmospheric pressure.', 'easy', 'science'
),
(
  'How many continents are there on Earth?',
  'كم عدد القارات على الأرض؟',
  '5', '6', '7', '8',
  '٥', '٦', '٧', '٨',
  'c', 'There are 7 continents: Africa, Antarctica, Asia, Australia, Europe, North America, South America.', 'easy', 'geography'
),
(
  'What is the currency of the United States?',
  'ما هي عملة الولايات المتحدة الأمريكية؟',
  'Pound', 'Euro', 'Yen', 'Dollar',
  'الجنيه', 'اليورو', 'الين', 'الدولار',
  'd', 'The US Dollar (USD) is the official currency of the United States.', 'easy', 'general'
),
(
  'Which fruit is known as the "king of fruits"?',
  'أي الفواكه يُعرف بـ"ملك الفاكهة"؟',
  'Mango', 'Apple', 'Banana', 'Orange',
  'المانجو', 'التفاح', 'الموز', 'البرتقال',
  'a', 'Mango is widely regarded as the "king of fruits" due to its taste and popularity.', 'easy', 'general'
),
(
  'How many legs does a spider have?',
  'كم عدد أرجل العنكبوت؟',
  '6', '8', '10', '4',
  '٦', '٨', '١٠', '٤',
  'b', 'Spiders are arachnids and have 8 legs, unlike insects which have 6.', 'easy', 'science'
),
(
  'What color is the sun?',
  'ما لون الشمس؟',
  'Orange', 'Yellow', 'White', 'Red',
  'برتقالي', 'أصفر', 'أبيض', 'أحمر',
  'c', 'The sun actually appears white from space; it looks yellow/orange from Earth due to our atmosphere.', 'easy', 'science'
),
(
  'What is the largest continent?',
  'ما هي أكبر قارة؟',
  'Africa', 'Americas', 'Asia', 'Europe',
  'أفريقيا', 'الأمريكتان', 'آسيا', 'أوروبا',
  'c', 'Asia is the world''s largest continent, covering about 44.6 million km².', 'easy', 'geography'
),
(
  'How many months have 31 days?',
  'كم عدد الأشهر التي تحتوي على 31 يومًا؟',
  '5', '6', '7', '8',
  '٥', '٦', '٧', '٨',
  'c', 'January, March, May, July, August, October, and December — 7 months have 31 days.', 'easy', 'general'
),
-- ── MEDIUM ───────────────────────────────────────────────────────────────────
(
  'What is the chemical symbol for gold?',
  'ما هو الرمز الكيميائي للذهب؟',
  'Go', 'Au', 'Ag', 'Gd',
  'Go', 'Au', 'Ag', 'Gd',
  'b', 'Au comes from the Latin word "Aurum," meaning gold.', 'medium', 'science'
),
(
  'Who invented the telephone?',
  'من اخترع الهاتف؟',
  'Thomas Edison', 'Nikola Tesla', 'Alexander Graham Bell', 'James Watt',
  'توماس إديسون', 'نيكولا تسلا', 'ألكسندر غراهام بيل', 'جيمس وات',
  'c', 'Alexander Graham Bell is credited with inventing and patenting the first telephone in 1876.', 'medium', 'science'
),
(
  'What is the largest planet in our solar system?',
  'ما هو أكبر كوكب في المجموعة الشمسية؟',
  'Saturn', 'Neptune', 'Uranus', 'Jupiter',
  'زحل', 'نبتون', 'أورانوس', 'المشتري',
  'd', 'Jupiter is the largest planet, with a mass more than twice that of all other planets combined.', 'medium', 'science'
),
(
  'What element has the atomic number 1?',
  'ما العنصر ذو الرقم الذري 1؟',
  'Hydrogen', 'Helium', 'Lithium', 'Carbon',
  'الهيدروجين', 'الهيليوم', 'الليثيوم', 'الكربون',
  'a', 'Hydrogen (H) is the simplest and most abundant element in the universe.', 'medium', 'science'
),
(
  'In which year did World War II end?',
  'في أي عام انتهت الحرب العالمية الثانية؟',
  '1943', '1944', '1946', '1945',
  '١٩٤٣', '١٩٤٤', '١٩٤٦', '١٩٤٥',
  'd', 'World War II ended in 1945, with Germany surrendering in May and Japan in September.', 'medium', 'history'
),
(
  'How many bones are in the adult human body?',
  'كم عدد العظام في جسم الإنسان البالغ؟',
  '198', '206', '212', '180',
  '١٩٨', '٢٠٦', '٢١٢', '١٨٠',
  'b', 'Adults have 206 bones. Babies are born with around 270–300, which fuse over time.', 'medium', 'science'
),
(
  'Which country has the most natural lakes?',
  'أي دولة تمتلك أكبر عدد من البحيرات الطبيعية؟',
  'Canada', 'Russia', 'USA', 'Finland',
  'كندا', 'روسيا', 'الولايات المتحدة', 'فنلندا',
  'a', 'Canada has about 879,800 lakes, more than any other country in the world.', 'medium', 'geography'
),
(
  'What is the national sport of Japan?',
  'ما هو الرياضة الوطنية لليابان؟',
  'Judo', 'Karate', 'Sumo', 'Kendo',
  'الجودو', 'الكاراتيه', 'السومو', 'الكيندو',
  'c', 'Sumo wrestling is the national sport of Japan, with a history of over 1,500 years.', 'medium', 'sports'
),
(
  'What is the longest river in the world?',
  'ما هو أطول نهر في العالم؟',
  'Amazon', 'Nile', 'Yangtze', 'Mississippi',
  'الأمازون', 'النيل', 'اليانغتسي', 'المسيسيبي',
  'b', 'The Nile River in Africa is generally considered the world''s longest river at about 6,650 km.', 'medium', 'geography'
),
(
  'What is the chemical formula for water?',
  'ما هي الصيغة الكيميائية للماء؟',
  'HO', 'H2O', 'H3O', 'OH2',
  'HO', 'H2O', 'H3O', 'OH2',
  'b', 'Water is composed of two hydrogen atoms and one oxygen atom: H₂O.', 'medium', 'science'
),
-- ── HARD ─────────────────────────────────────────────────────────────────────
(
  'What is the 10th number in the Fibonacci sequence?',
  'ما هو الرقم العاشر في متتالية فيبوناتشي؟',
  '34', '55', '44', '89',
  '٣٤', '٥٥', '٤٤', '٨٩',
  'b', 'The Fibonacci sequence: 1,1,2,3,5,8,13,21,34,55 — the 10th number is 55.', 'hard', 'math'
),
(
  'Which organ in the human body produces insulin?',
  'أي عضو في الجسم البشري يُنتج الأنسولين؟',
  'Liver', 'Kidney', 'Spleen', 'Pancreas',
  'الكبد', 'الكلية', 'الطحال', 'البنكرياس',
  'd', 'The pancreas produces insulin, which regulates blood sugar levels.', 'hard', 'science'
),
(
  'What is the chemical formula for table salt?',
  'ما هي الصيغة الكيميائية لملح الطعام؟',
  'KCl', 'NaCl', 'MgCl2', 'CaCl2',
  'KCl', 'NaCl', 'MgCl2', 'CaCl2',
  'b', 'Table salt is sodium chloride (NaCl), composed of sodium and chlorine ions.', 'hard', 'science'
),
(
  'In what year was the Magna Carta signed?',
  'في أي عام وُقِّعت الماغنا كارتا؟',
  '1066', '1215', '1307', '1455',
  '١٠٦٦', '١٢١٥', '١٣٠٧', '١٤٥٥',
  'b', 'The Magna Carta was signed by King John of England on June 15, 1215.', 'hard', 'history'
),
(
  'How many symphonies did Beethoven compose?',
  'كم سيمفونية ألّف بيتهوفن؟',
  '7', '8', '9', '10',
  '٧', '٨', '٩', '١٠',
  'c', 'Beethoven composed 9 symphonies, the last being the famous Symphony No. 9 in D minor.', 'hard', 'arts'
),
(
  'Which programming language was created by James Gosling?',
  'من ابتكر لغة البرمجة جافا؟',
  'C++', 'Python', 'Ruby', 'Java',
  'سي++', 'بايثون', 'روبي', 'جافا',
  'd', 'James Gosling created Java at Sun Microsystems, first released in 1995.', 'hard', 'technology'
),
(
  'What is the approximate half-life of Carbon-14?',
  'ما هو عمر النصف التقريبي للكربون-14؟',
  '5,730 years', '1,000 years', '10,000 years', '500 years',
  '٥٧٣٠ سنة', '١٠٠٠ سنة', '١٠٠٠٠ سنة', '٥٠٠ سنة',
  'a', 'Carbon-14 has a half-life of approximately 5,730 years, used in radiocarbon dating.', 'hard', 'science'
),
(
  'In what city was William Shakespeare born?',
  'في أي مدينة وُلد ويليام شكسبير؟',
  'London', 'Oxford', 'Stratford-upon-Avon', 'Cambridge',
  'لندن', 'أكسفورد', 'ستراتفورد أبون إيفون', 'كامبريدج',
  'c', 'Shakespeare was born in Stratford-upon-Avon, England, in April 1564.', 'hard', 'arts'
),
(
  'What is the speed of light in a vacuum (km/s)?',
  'ما هي سرعة الضوء في الفراغ (كم/ث)؟',
  '150,000', '300,000', '500,000', '250,000',
  '١٥٠٬٠٠٠', '٣٠٠٬٠٠٠', '٥٠٠٬٠٠٠', '٢٥٠٬٠٠٠',
  'b', 'The speed of light in a vacuum is approximately 299,792 km/s, often rounded to 300,000 km/s.', 'hard', 'science'
),
(
  'Who painted the Sistine Chapel ceiling?',
  'من رسم سقف كنيسة سيستين؟',
  'Leonardo da Vinci', 'Raphael', 'Michelangelo', 'Donatello',
  'ليوناردو دافنشي', 'رافائيل', 'مايكل أنجلو', 'دوناتيلو',
  'c', 'Michelangelo painted the Sistine Chapel ceiling between 1508 and 1512.', 'hard', 'arts'
);

-- ── 7. start_gold_ladder_run RPC ─────────────────────────────────────────────

create or replace function public.start_gold_ladder_run(
  p_entry_fee integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id    uuid := auth.uid();
  v_run_id     uuid := gen_random_uuid();
  v_new_balance integer;
  v_question_ids uuid[];
  v_first_q    record;
  v_ladder     jsonb;
  v_prizes     numeric[] := array[1,1.5,2,3,5,7,10,15,20,30,50,100];
  i            integer;
  v_ladder_arr jsonb[] := array[]::jsonb[];
  v_safe_qs    integer[] := array[5,10];
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  if p_entry_fee not in (100, 500, 1000) then
    raise exception 'invalid_entry_fee';
  end if;

  -- Deduct entry fee atomically
  update public.wallets
  set    coins_balance         = coins_balance - p_entry_fee,
         lifetime_coins_spent  = lifetime_coins_spent + p_entry_fee,
         updated_at            = now()
  where  user_id = v_user_id
  and    coins_balance >= p_entry_fee
  returning coins_balance into v_new_balance;

  if not found then
    raise exception 'insufficient_coins';
  end if;

  -- Record wallet transaction
  insert into public.wallet_transactions
    (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
  values
    (v_user_id, 'gold_ladder_entry', 'debit', -p_entry_fee, 0,
     'Gold Ladder Quiz entry fee',
     jsonb_build_object('run_id', v_run_id, 'entry_fee', p_entry_fee));

  -- Select 12 questions: 4 easy (Q1-4), 4 medium (Q5-8), 4 hard (Q9-12)
  select array_agg(q_id order by random()) into v_question_ids
  from (
    (select id as q_id from public.gold_ladder_questions
     where difficulty = 'easy' and is_active = true order by random() limit 4)
    union all
    (select id from public.gold_ladder_questions
     where difficulty = 'medium' and is_active = true order by random() limit 4)
    union all
    (select id from public.gold_ladder_questions
     where difficulty = 'hard' and is_active = true order by random() limit 4)
  ) q;

  -- Check we have enough questions
  if array_length(v_question_ids, 1) < 12 then
    -- Refund and abort
    update public.wallets
    set coins_balance = coins_balance + p_entry_fee, updated_at = now()
    where user_id = v_user_id;
    raise exception 'insufficient_questions';
  end if;

  -- Create run
  insert into public.gold_ladder_runs
    (id, user_id, entry_fee, question_ids, status, powers_remaining)
  values
    (v_run_id, v_user_id, p_entry_fee, v_question_ids, 'active',
     '{"remove_two":1,"crowd_pulse":1,"second_chance":1}'::jsonb);

  -- Fetch first question (no correct_option sent)
  select id, text, text_ar,
         option_a, option_b, option_c, option_d,
         option_a_ar, option_b_ar, option_c_ar, option_d_ar,
         difficulty
  into v_first_q
  from public.gold_ladder_questions
  where id = v_question_ids[1];

  -- Build ladder with prizes
  for i in 1..12 loop
    v_ladder_arr := v_ladder_arr || jsonb_build_object(
      'q',          i,
      'multiplier', v_prizes[i],
      'prize',      (p_entry_fee * v_prizes[i])::integer,
      'safe',       (i = any(v_safe_qs))
    );
  end loop;
  v_ladder := array_to_json(v_ladder_arr)::jsonb;

  return jsonb_build_object(
    'run_id',        v_run_id,
    'entry_fee',     p_entry_fee,
    'balance',       v_new_balance,
    'question_number', 1,
    'current_prize', (p_entry_fee * v_prizes[1])::integer,
    'question', jsonb_build_object(
      'id',         v_first_q.id,
      'text',       v_first_q.text,
      'text_ar',    v_first_q.text_ar,
      'option_a',   v_first_q.option_a,
      'option_b',   v_first_q.option_b,
      'option_c',   v_first_q.option_c,
      'option_d',   v_first_q.option_d,
      'option_a_ar',v_first_q.option_a_ar,
      'option_b_ar',v_first_q.option_b_ar,
      'option_c_ar',v_first_q.option_c_ar,
      'option_d_ar',v_first_q.option_d_ar,
      'difficulty', v_first_q.difficulty
    ),
    'ladder',        v_ladder,
    'powers_remaining', '{"remove_two":1,"crowd_pulse":1,"second_chance":1}'::jsonb
  );
end;
$$;

grant execute on function public.start_gold_ladder_run(integer) to authenticated;

-- ── 8. answer_gold_ladder_question RPC ──────────────────────────────────────

create or replace function public.answer_gold_ladder_question(
  p_run_id          uuid,
  p_question_id     uuid,
  p_selected_option text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id      uuid := auth.uid();
  v_run          public.gold_ladder_runs;
  v_q            public.gold_ladder_questions;
  v_is_correct   boolean;
  v_next_num     integer;
  v_next_q       record;
  v_cashout      integer := 0;
  v_new_balance  integer;
  v_prizes       numeric[] := array[1,1.5,2,3,5,7,10,15,20,30,50,100];
  v_safe_qs      integer[] := array[5,10];
  v_safe_payouts integer[] := array[5, 30]; -- multipliers for safe q5 and q10
  v_new_safe     integer;
  i              integer;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  if p_selected_option not in ('a','b','c','d') then
    raise exception 'invalid_option';
  end if;

  -- Lock and fetch run
  select * into v_run
  from public.gold_ladder_runs
  where id = p_run_id and user_id = v_user_id
  for update;

  if not found then raise exception 'run_not_found'; end if;
  if v_run.status != 'active' then raise exception 'run_not_active'; end if;

  -- Verify question matches current slot
  if v_run.question_ids[v_run.current_question_num] != p_question_id then
    raise exception 'wrong_question';
  end if;

  -- Fetch correct answer
  select * into v_q from public.gold_ladder_questions where id = p_question_id;

  v_is_correct := (v_q.correct_option = p_selected_option);

  if v_is_correct then
    -- ── Correct ─────────────────────────────────────────────────────────────
    v_next_num := v_run.current_question_num + 1;

    -- Check if this question was a safe point
    v_new_safe := v_run.highest_safe_question;
    if v_run.current_question_num = any(v_safe_qs) then
      v_new_safe := greatest(v_new_safe, v_run.current_question_num);
    end if;

    if v_run.current_question_num = 12 then
      -- ── Won! ────────────────────────────────────────────────────────────
      v_cashout := (v_run.entry_fee * 100)::integer;

      update public.wallets
      set coins_balance = coins_balance + v_cashout, updated_at = now()
      where user_id = v_user_id
      returning coins_balance into v_new_balance;

      insert into public.wallet_transactions
        (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
      values
        (v_user_id, 'gold_ladder_win', 'credit', v_cashout, 0,
         'Gold Ladder Quiz — completed all 12 questions',
         jsonb_build_object('run_id', p_run_id, 'entry_fee', v_run.entry_fee));

      insert into public.gold_ladder_answers
        (run_id, question_id, question_number, selected_option, is_correct)
      values (p_run_id, p_question_id, v_run.current_question_num, p_selected_option, true);

      update public.gold_ladder_runs
      set status = 'completed', current_question_num = 13,
          highest_safe_question = 10, cashout_amount = v_cashout
      where id = p_run_id;

      return jsonb_build_object(
        'correct',          true,
        'correct_option',   v_q.correct_option,
        'explanation',      v_q.explanation,
        'question_number',  v_run.current_question_num,
        'is_completed',     true,
        'is_eliminated',    false,
        'cashout_amount',   v_cashout,
        'new_balance',      v_new_balance,
        'current_prize',    v_cashout,
        'second_chance_triggered', false
      );

    else
      -- ── Advance to next question ─────────────────────────────────────────
      insert into public.gold_ladder_answers
        (run_id, question_id, question_number, selected_option, is_correct)
      values (p_run_id, p_question_id, v_run.current_question_num, p_selected_option, true);

      update public.gold_ladder_runs
      set current_question_num = v_next_num,
          highest_safe_question = v_new_safe,
          second_chance_active = false
      where id = p_run_id;

      -- Fetch next question (no correct_option)
      select id, text, text_ar,
             option_a, option_b, option_c, option_d,
             option_a_ar, option_b_ar, option_c_ar, option_d_ar,
             difficulty
      into v_next_q
      from public.gold_ladder_questions
      where id = v_run.question_ids[v_next_num];

      return jsonb_build_object(
        'correct',          true,
        'correct_option',   v_q.correct_option,
        'explanation',      v_q.explanation,
        'question_number',  v_run.current_question_num,
        'is_completed',     false,
        'is_eliminated',    false,
        'second_chance_triggered', false,
        'next_question_number', v_next_num,
        'current_prize',    (v_run.entry_fee * v_prizes[v_run.current_question_num])::integer,
        'next_question', jsonb_build_object(
          'id',          v_next_q.id,
          'text',        v_next_q.text,
          'text_ar',     v_next_q.text_ar,
          'option_a',    v_next_q.option_a,
          'option_b',    v_next_q.option_b,
          'option_c',    v_next_q.option_c,
          'option_d',    v_next_q.option_d,
          'option_a_ar', v_next_q.option_a_ar,
          'option_b_ar', v_next_q.option_b_ar,
          'option_c_ar', v_next_q.option_c_ar,
          'option_d_ar', v_next_q.option_d_ar,
          'difficulty',  v_next_q.difficulty
        )
      );
    end if;

  else
    -- ── Wrong answer ─────────────────────────────────────────────────────────

    -- Check second chance
    if v_run.second_chance_active then
      -- Give another attempt; don't record or reveal correct answer
      update public.gold_ladder_runs
      set second_chance_active = false
      where id = p_run_id;

      return jsonb_build_object(
        'correct',          false,
        'correct_option',   null,  -- not revealed yet
        'question_number',  v_run.current_question_num,
        'is_eliminated',    false,
        'is_completed',     false,
        'second_chance_triggered', true,
        'current_prize',    (v_run.entry_fee * v_prizes[v_run.current_question_num])::integer
      );
    end if;

    -- Record wrong answer
    insert into public.gold_ladder_answers
      (run_id, question_id, question_number, selected_option, is_correct)
    values (p_run_id, p_question_id, v_run.current_question_num, p_selected_option, false);

    -- Pay out safe amount
    if v_run.highest_safe_question = 5 then
      v_cashout := (v_run.entry_fee * 5)::integer;
    elsif v_run.highest_safe_question = 10 then
      v_cashout := (v_run.entry_fee * 30)::integer;
    else
      v_cashout := 0;
    end if;

    if v_cashout > 0 then
      update public.wallets
      set coins_balance = coins_balance + v_cashout, updated_at = now()
      where user_id = v_user_id
      returning coins_balance into v_new_balance;

      insert into public.wallet_transactions
        (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
      values
        (v_user_id, 'gold_ladder_safe_payout', 'credit', v_cashout, 0,
         'Gold Ladder Quiz — safe point payout',
         jsonb_build_object('run_id', p_run_id, 'safe_q', v_run.highest_safe_question));
    else
      select coins_balance into v_new_balance
      from public.wallets where user_id = v_user_id;
    end if;

    update public.gold_ladder_runs
    set status = 'eliminated', cashout_amount = v_cashout
    where id = p_run_id;

    return jsonb_build_object(
      'correct',         false,
      'correct_option',  v_q.correct_option,
      'explanation',     v_q.explanation,
      'question_number', v_run.current_question_num,
      'is_eliminated',   true,
      'is_completed',    false,
      'second_chance_triggered', false,
      'cashout_amount',  v_cashout,
      'new_balance',     v_new_balance,
      'current_prize',   (v_run.entry_fee * v_prizes[v_run.current_question_num])::integer
    );
  end if;
end;
$$;

grant execute on function public.answer_gold_ladder_question(uuid, uuid, text) to authenticated;

-- ── 9. use_gold_ladder_power RPC ─────────────────────────────────────────────

create or replace function public.use_gold_ladder_power(
  p_run_id     uuid,
  p_question_id uuid,
  p_power_type text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id    uuid := auth.uid();
  v_run        public.gold_ladder_runs;
  v_correct    char(1);
  v_wrong_opts text[];
  v_elim       text[];
  v_total      integer;
  v_dist       jsonb;
  v_pcts       integer[] := array[0,0,0,0];
  v_remainder  integer;
  v_correct_idx integer;
  v_opts       text[] := array['a','b','c','d'];
  i            integer;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  if p_power_type not in ('remove_two','crowd_pulse','second_chance') then
    raise exception 'invalid_power_type';
  end if;

  select * into v_run
  from public.gold_ladder_runs
  where id = p_run_id and user_id = v_user_id
  for update;

  if not found then raise exception 'run_not_found'; end if;
  if v_run.status != 'active' then raise exception 'run_not_active'; end if;

  if v_run.question_ids[v_run.current_question_num] != p_question_id then
    raise exception 'wrong_question';
  end if;

  -- Check power available
  if coalesce((v_run.powers_remaining->>p_power_type)::integer, 0) < 1 then
    raise exception 'power_not_available';
  end if;

  -- Deduct power
  update public.gold_ladder_runs
  set powers_remaining = jsonb_set(
    powers_remaining,
    array[p_power_type],
    to_jsonb(coalesce((powers_remaining->>p_power_type)::integer, 1) - 1)
  )
  where id = p_run_id;

  select correct_option into v_correct
  from public.gold_ladder_questions where id = p_question_id;

  if p_power_type = 'remove_two' then
    -- Pick 2 of the 3 wrong options to eliminate
    select array_agg(opt order by random()) into v_elim
    from unnest(v_opts) as opt
    where opt != v_correct
    limit 2;

    return jsonb_build_object(
      'power_type',       'remove_two',
      'eliminated_options', to_jsonb(v_elim)
    );

  elsif p_power_type = 'crowd_pulse' then
    -- Give correct answer ~50-70% of the audience, spread rest randomly
    v_correct_idx := array_position(v_opts, v_correct::text);

    -- Correct: 50-70%
    v_pcts[v_correct_idx] := 50 + floor(random() * 21)::integer;
    v_remainder := 100 - v_pcts[v_correct_idx];

    -- Distribute remainder across the other 3 options
    declare
      v_split1 integer := floor(random() * (v_remainder - 3))::integer + 1;
      v_split2 integer := floor(random() * (v_remainder - v_split1 - 2))::integer + 1;
      v_split3 integer := v_remainder - v_split1 - v_split2;
      v_others integer[] := array[]::integer[];
      j integer;
    begin
      v_others := array[v_split1, v_split2, v_split3];
      j := 1;
      for i in 1..4 loop
        if i != v_correct_idx then
          v_pcts[i] := v_others[j];
          j := j + 1;
        end if;
      end loop;
    end;

    return jsonb_build_object(
      'power_type', 'crowd_pulse',
      'distribution', jsonb_build_object(
        'a', v_pcts[1],
        'b', v_pcts[2],
        'c', v_pcts[3],
        'd', v_pcts[4]
      )
    );

  else -- second_chance
    update public.gold_ladder_runs
    set second_chance_active = true
    where id = p_run_id;

    return jsonb_build_object(
      'power_type', 'second_chance',
      'confirmed',  true
    );
  end if;
end;
$$;

grant execute on function public.use_gold_ladder_power(uuid, uuid, text) to authenticated;

-- ── 10. cashout_gold_ladder_run RPC ─────────────────────────────────────────

create or replace function public.cashout_gold_ladder_run(
  p_run_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id     uuid := auth.uid();
  v_run         public.gold_ladder_runs;
  v_cashout     integer;
  v_new_balance integer;
begin
  if v_user_id is null then raise exception 'not_authenticated'; end if;

  select * into v_run
  from public.gold_ladder_runs
  where id = p_run_id and user_id = v_user_id
  for update;

  if not found then raise exception 'run_not_found'; end if;
  if v_run.status != 'active' then raise exception 'run_not_active'; end if;

  if v_run.highest_safe_question = 5 then
    v_cashout := (v_run.entry_fee * 5)::integer;
  elsif v_run.highest_safe_question = 10 then
    v_cashout := (v_run.entry_fee * 30)::integer;
  else
    v_cashout := 0;
  end if;

  if v_cashout > 0 then
    update public.wallets
    set coins_balance = coins_balance + v_cashout, updated_at = now()
    where user_id = v_user_id
    returning coins_balance into v_new_balance;

    insert into public.wallet_transactions
      (user_id, type, direction, coins_delta, diamonds_delta, note, metadata)
    values
      (v_user_id, 'gold_ladder_safe_payout', 'credit', v_cashout, 0,
       'Gold Ladder Quiz — voluntary cash out',
       jsonb_build_object('run_id', p_run_id));
  else
    select coins_balance into v_new_balance
    from public.wallets where user_id = v_user_id;
  end if;

  update public.gold_ladder_runs
  set status = 'cashed_out', cashout_amount = v_cashout
  where id = p_run_id;

  return jsonb_build_object(
    'cashout_amount', v_cashout,
    'new_balance',    v_new_balance
  );
end;
$$;

grant execute on function public.cashout_gold_ladder_run(uuid) to authenticated;

-- ── 11. get_gold_ladder_recent_winners RPC ───────────────────────────────────

create or replace function public.get_gold_ladder_recent_winners(
  p_limit integer default 10
)
returns table (
  display_name text,
  entry_fee    integer,
  cashout_amount integer,
  multiplier   numeric,
  status       text,
  created_at   timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return query
  select
    coalesce(pr.display_name, 'Player') as display_name,
    r.entry_fee,
    r.cashout_amount,
    case when r.entry_fee > 0 then round(r.cashout_amount::numeric / r.entry_fee, 1) else 0 end as multiplier,
    r.status,
    r.created_at
  from public.gold_ladder_runs r
  left join public.profiles pr on pr.id = r.user_id
  where r.status in ('completed','cashed_out','eliminated')
    and r.cashout_amount > 0
  order by r.created_at desc
  limit p_limit;
end;
$$;

grant execute on function public.get_gold_ladder_recent_winners(integer) to authenticated;
