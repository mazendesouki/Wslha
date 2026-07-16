-- تشخيص: استبدل القيمتين تحت باللي كتبته فعليًا في النافذتين، وشغّل الاستعلامين.

-- 1) هل مفتاح الأمان صح؟ (المفروض يطلع true)
select public.verify_action_key('AdminEG2310');

-- 2) هل كلمة مرور المشرف صح؟ (يطلع صف "مازن ديسوقي" — شوف عمود password_matches)
select phone, role, name,
       (password = extensions.crypt('Mdesouki242249895', password)) as password_matches
  from public.accounts
 where role = 'admin';
