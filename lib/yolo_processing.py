from ultralytics import YOLO

# تحميل نموذج مدرب مسبقًا
model = YOLO("yolov8n-oiv7.pt")

# إجراء التنبؤات على صورة
results = model.predict(source=0)

# عرض النتائج
# افترض أن النتائج هي قائمة
results = model.predict(source=0)

# تحقق من أن النتائج ليست فارغة
if results:
    # الوصول إلى العنصر الأول في القائمة
    first_result = results[0]
    # الآن يمكنك استدعاء الدالة show() على الكائن الأول
    first_result.show()
else:
    print("No results found.")
