// DRAFT terms of use and privacy policy, in English and Arabic.
// Have a lawyer in Egypt review both before inviting members beyond a small pilot.
// Update [legalUpdated] whenever the text changes.

const legalUpdated = '2026-11-26';

class LegalSection {
  const LegalSection(this.title, this.body);
  final String title;
  final String body;
}

const termsEn = [
  LegalSection('What DentPass is',
      'DentPass connects licensed dentists and dental assistants in Egypt so they can offer and book seats to watch a case, courses, chairs or units for rent, and shift cover. DentPass is not a clinic, does not provide dental treatment, and is not a party to any arrangement between members.'),
  LegalSection('Who can join',
      'You must be at least 21 and a dentist registered with the Egyptian Dental Syndicate, or a dental assistant. You agree to send true details and documents, and to keep your licence valid. We may refuse, suspend or remove an account that does not meet these terms.'),
  LegalSection('Your responsibilities',
      'Hosts and guests are each responsible for their own professional conduct, licences, insurance and compliance with Egyptian law and syndicate rules. Anyone treating a patient is responsible for that treatment. Hosts of observation slots and courses must have each patient\'s informed consent for observers. Hosts renting a chair or unit must make sure the equipment is safe, sterilised and legal to use.'),
  LegalSection('Bookings and payment',
      'A request becomes a booking only when the host accepts it. For now, members pay each other directly, for example by InstaPay, after acceptance. The DentPass fee, if any, is shown before you send a request. Agree any cancellation terms with the other member; DentPass does not hold or refund payments.'),
  LegalSection('Ratings and reports',
      'Ratings must be honest and about the slot. Report anything unsafe, fake or abusive from the member\'s page or the slot. We review reports and may remove content or suspend accounts.'),
  LegalSection('Not allowed',
      'Fake identities or documents; sharing patients\' personal or medical information in the app; harassment; posting slots that break the law or syndicate rules; using the app to contact members for unrelated selling.'),
  LegalSection('Liability',
      'DentPass is provided as it is. To the extent the law allows, DentPass is not responsible for what happens during a slot, for members\' conduct, or for losses between members. Nothing here limits rights you have under Egyptian consumer law.'),
  LegalSection('Changes and ending',
      'We may update these terms; we will tell you in the app. You can delete your account at any time from Profile. These terms are governed by the laws of the Arab Republic of Egypt.'),
];

const termsAr = [
  LegalSection('ما هو دنت باس',
      'يربط دنت باس أطباء الأسنان ومساعديهم المرخصين في مصر، ليعرضوا ويحجزوا مقاعد لمشاهدة الحالات، والكورسات، والكراسي أو الوحدات للإيجار، وتغطية الشيفتات. دنت باس ليس عيادة، ولا يقدم علاجًا، وليس طرفًا في أي اتفاق بين الأعضاء.'),
  LegalSection('من يمكنه الانضمام',
      'يجب ألا يقل عمرك عن 21 عامًا، وأن تكون طبيب أسنان مقيدًا بنقابة أطباء الأسنان المصرية أو مساعد طبيب أسنان. توافق على تقديم بيانات ومستندات صحيحة، والحفاظ على سريان ترخيصك. يجوز لنا رفض أو إيقاف أو حذف أي حساب لا يلتزم بهذه الشروط.'),
  LegalSection('مسؤولياتك',
      'كل من المضيف والضيف مسؤول عن سلوكه المهني وتراخيصه وتأمينه والتزامه بالقانون المصري ولوائح النقابة. من يعالج مريضًا مسؤول عن هذا العلاج. على مضيفي مواعيد المشاهدة والكورسات الحصول على موافقة مستنيرة من كل مريض على وجود مشاهدين. وعلى من يؤجر كرسيًا أو وحدة التأكد من أن المعدات آمنة ومعقمة ويجوز استخدامها قانونًا.'),
  LegalSection('الحجز والدفع',
      'لا يصبح الطلب حجزًا إلا بعد قبول المضيف. حاليًا يدفع الأعضاء لبعضهم مباشرة، مثلًا عبر إنستاباي، بعد القبول. تظهر رسوم دنت باس، إن وجدت، قبل إرسال الطلب. اتفقوا على شروط الإلغاء فيما بينكم؛ لا يحتفظ دنت باس بالمدفوعات ولا يردها.'),
  LegalSection('التقييمات والبلاغات',
      'يجب أن تكون التقييمات صادقة وتخص الموعد. أبلغ عن أي شيء غير آمن أو مزيف أو مسيء من صفحة العضو أو الموعد. نراجع البلاغات ويجوز لنا حذف المحتوى أو إيقاف الحسابات.'),
  LegalSection('غير مسموح',
      'الهويات أو المستندات المزيفة؛ مشاركة بيانات المرضى الشخصية أو الطبية داخل التطبيق؛ التحرش؛ نشر مواعيد تخالف القانون أو لوائح النقابة؛ استخدام التطبيق للتواصل مع الأعضاء لبيع أمور لا علاقة لها بالتطبيق.'),
  LegalSection('المسؤولية',
      'يُقدَّم دنت باس كما هو. وفي حدود ما يسمح به القانون، لا يتحمل دنت باس مسؤولية ما يحدث أثناء الموعد، أو سلوك الأعضاء، أو الخسائر بينهم. لا يقيّد شيء هنا حقوقك وفق قانون حماية المستهلك المصري.'),
  LegalSection('التعديل والإنهاء',
      'يجوز لنا تحديث هذه الشروط وسنُعلمك داخل التطبيق. يمكنك حذف حسابك في أي وقت من «حسابي». تخضع هذه الشروط لقوانين جمهورية مصر العربية.'),
];

const privacyEn = [
  LegalSection('What we collect',
      'Your email and password (stored securely by our provider), name, mobile number, role, syndicate number, area, photos of your syndicate card and national ID, your profile photo and bio, the slots you post (including photos and an optional map location), your requests, ratings, reports, and the phones you turn notifications on for. If you use "Near me", your location is used on your phone to sort slots and is not saved.'),
  LegalSection('Why we use it',
      'To check that members are licensed; to run posting, booking, ratings and notifications; to keep the community safe; and to contact you about your account.'),
  LegalSection('Who can see what',
      'Your documents and phone number are seen only by DentPass admins. Other members see your name, role, area, photo, bio and ratings. Your phone number and a slot\'s exact address and map pin are shared only between two members after a request is accepted. Before that, maps show an area of about 1 km.'),
  LegalSection('Services we use',
      'Supabase stores the database and files. GitHub Pages hosts the app. Map pictures come from OpenStreetMap. Phone notifications pass through Apple\'s or Google\'s notification service. Some of these services may store data outside Egypt. We do not sell your data.'),
  LegalSection('How long we keep it',
      'For as long as your account exists. When you delete your account in Profile, your details, documents, slots, bookings and photos are deleted. Ratings you gave are deleted too.'),
  LegalSection('Your rights',
      'You can see and correct your details in Profile, and delete your account at any time. For any other request, contact us through Help and contact. We follow Egypt\'s Personal Data Protection Law (Law No. 151 of 2020).'),
];

const privacyAr = [
  LegalSection('ما الذي نجمعه',
      'بريدك الإلكتروني وكلمة المرور (يحفظها مزود الخدمة بشكل آمن)، والاسم، ورقم الموبايل، والدور، ورقم القيد بالنقابة، والمنطقة، وصور كارنيه النقابة والبطاقة الشخصية، وصورة حسابك ونبذتك، والمواعيد التي تنشرها (بما فيها الصور وموقع اختياري على الخريطة)، وطلباتك، وتقييماتك، وبلاغاتك، والهواتف التي فعّلت عليها الإشعارات. عند استخدام «بالقرب مني» يُستخدم موقعك على هاتفك لترتيب المواعيد ولا يُحفظ.'),
  LegalSection('لماذا نستخدمه',
      'للتحقق من أن الأعضاء مرخصون؛ ولتشغيل النشر والحجز والتقييمات والإشعارات؛ وللحفاظ على أمان المجتمع؛ وللتواصل معك بخصوص حسابك.'),
  LegalSection('من يرى ماذا',
      'لا يرى مستنداتك ورقم هاتفك إلا مسؤولو دنت باس. ويرى الأعضاء الآخرون اسمك ودورك ومنطقتك وصورتك ونبذتك وتقييماتك. لا يُشارك رقم هاتفك والعنوان الدقيق للموعد وموقعه على الخريطة إلا بين عضوين بعد قبول الطلب. وقبل ذلك تُظهر الخريطة منطقة تقريبية بحدود 1 كم.'),
  LegalSection('الخدمات التي نستخدمها',
      'تحفظ Supabase قاعدة البيانات والملفات، وتستضيف GitHub Pages التطبيق، وتأتي صور الخرائط من OpenStreetMap، وتمر إشعارات الهاتف عبر خدمة إشعارات أبل أو جوجل. قد تحفظ بعض هذه الخدمات البيانات خارج مصر. نحن لا نبيع بياناتك.'),
  LegalSection('مدة الاحتفاظ',
      'طوال وجود حسابك. عند حذف حسابك من «حسابي» تُحذف بياناتك ومستنداتك ومواعيدك وحجوزاتك وصورك، وتُحذف أيضًا التقييمات التي كتبتها.'),
  LegalSection('حقوقك',
      'يمكنك رؤية بياناتك وتصحيحها من «حسابي»، وحذف حسابك في أي وقت. لأي طلب آخر تواصل معنا من «المساعدة والتواصل». نلتزم بقانون حماية البيانات الشخصية المصري (القانون رقم 151 لسنة 2020).'),
];
