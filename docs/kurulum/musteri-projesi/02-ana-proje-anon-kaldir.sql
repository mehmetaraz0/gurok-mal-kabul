-- Edge Function artık service_role ile çağırıyor; anon'un doğrudan çağırmasına gerek yok
-- (DoS/sahte-rezervasyon yüzeyini kapatır). authenticated (personel) korunur.
-- ANA projede (xwytofysmgqtqjzkplfi) çalıştırılır.
begin;
revoke execute on function public.bar_siparis_olustur(text,text,text,text,jsonb) from anon;
commit;
