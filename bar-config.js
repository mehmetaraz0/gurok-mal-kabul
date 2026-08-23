// bar-config.js — Bar/QR müşteri projesi (fiziksel izolasyon) bağlantı sabitleri.
// Bu sabitler daha önce 5 ayrı bar-*.html'de kopyalanmıştı; tek kaynak burası.
// Anon key public-by-design'tır; güvenlik RLS + Edge Function (hyper-api) JWT
// doğrulamasıyla sağlanır. Yeni müşteri kurulumunda SADECE bu dosya güncellenir.

const CUSTOMER_SB_URL = 'https://udjpcsjifgdzvfflezaa.supabase.co';
const CUSTOMER_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVkanBjc2ppZmdkenZmZmxlemFhIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ4OTkzOTksImV4cCI6MjEwMDQ3NTM5OX0.cT-TZ5EImk2MEDuOzMuTpogYeoj8u7ovfO4C5EBM7bc';
