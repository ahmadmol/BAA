from ultralytics import YOLO
import cv2
import multiprocessing

if __name__ == '__main__':
    multiprocessing.freeze_support()

    # تحميل النموذج المدرب (بعد التدريب)
    model = YOLO("yolov8n.pt")  # أو "yolov8n.pt" لو أردت النموذج الجاهز

    # تحديد مسار الصورة
    # image_path = "C:/Users/WIN 10/Desktop/test1.jpg"
    image="C:\Users\WIN 10\Desktop\BAA\test1"
    # تنفيذ التنبؤ مع عرض الصورة وحفظها
    results = model(image, show=True)
     
    # for r in results:
    #     annotated_img = r.plot()

    #     # تحديد مسار الحفظ
    #     save_path = "C:/Users/WIN 10/Desktop/BAA/result.jpg"
    #     cv2.imwrite(save_path, annotated_img)
    #     print(f"تم حفظ الصورة في: {save_path}")
