-- Fix corrupted Arabic gift names using Unicode escape strings.
-- This avoids PowerShell and terminal encoding corruption.

update public.gifts set arabic_name = U&'\0643\0646\0632' where code = 'treasure';
update public.gifts set arabic_name = U&'\0648\0631\062F\0629' where code = 'rose';
update public.gifts set arabic_name = U&'\0646\062C\0645\0629' where code = 'star';
update public.gifts set arabic_name = U&'\062A\0627\062C' where code = 'crown';
update public.gifts set arabic_name = U&'\0635\0627\0631\0648\062E' where code = 'rocket';
update public.gifts set arabic_name = U&'\0623\0644\0645\0627\0633\0629' where code = 'diamond';
update public.gifts set arabic_name = U&'\0646\0645\0631' where code = 'tiger';
update public.gifts set arabic_name = U&'\062D\0642\064A\0628\0629 \0627\0644\062D\0638' where code = 'lucky_bag';
update public.gifts set arabic_name = U&'\062F\0631\0627\062C\0629' where code = 'motorcycle';
update public.gifts set arabic_name = U&'\0645\0642\0644\0627\0639' where code = 'slingshot';
update public.gifts set arabic_name = U&'\062A\0646\064A\0646' where code = 'dragon';
update public.gifts set arabic_name = U&'\0642\0644\0639\0629' where code = 'castle';
update public.gifts set arabic_name = U&'\0627\0644\0623\0633\062F \0627\0644\0630\0647\0628\064A' where code = 'golden_lion';
update public.gifts set arabic_name = U&'\0642\0644\0639\0629 \0628\0639\0644\0628\0643' where code = 'baalbek_temple';
