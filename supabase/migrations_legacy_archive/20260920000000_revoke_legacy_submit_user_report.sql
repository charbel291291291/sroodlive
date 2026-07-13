-- Security fix: revoke legacy submit_user_report(text,text,text,text) from authenticated
--
-- Some databases may not have this legacy RPC because it was removed or never
-- applied. Keep this migration idempotent: revoke only when the exact function
-- signature exists.

do $$
begin
  if to_regprocedure('public.submit_user_report(text,text,text,text)') is not null then
    execute 'revoke execute on function public.submit_user_report(text,text,text,text) from authenticated';
  end if;
end $$;