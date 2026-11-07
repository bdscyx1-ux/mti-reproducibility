using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace CY.DDMFinal.InputManager
{
    public static class MultiSelection
    {
        private static Texture2D _whiteTexture;

        public static Texture2D WhiteTexture
        {
            get
            {
                if (_whiteTexture == null)
                {
                    _whiteTexture = new Texture2D(1, 1);
                    _whiteTexture.SetPixel(0, 0, Color.white);
                    _whiteTexture.Apply();
                }
                return _whiteTexture;
            }
        }

        public static void DrawScreenRect(Rect rect, Color color)
        {
            GUI.color = color;
            GUI.DrawTexture(rect, WhiteTexture);
        }

        public static void DrawScreenRectBoarder(Rect rect, float thinkness, Color color)
        {
            //Top boarder
            DrawScreenRect(new Rect(rect.xMin, rect.yMin, rect.width, thinkness), color);
            //Bottom boarder
            DrawScreenRect(new Rect(rect.xMin, rect.yMax - thinkness, rect.width, thinkness), color);
            //Left boarder
            DrawScreenRect(new Rect(rect.xMin, rect.yMin, thinkness, rect.height), color);
            //Right boarder
            DrawScreenRect(new Rect(rect.xMax - thinkness, rect.yMin, thinkness, rect.height), color);
        }

        public static Rect GetScreenRect(Vector3 screenPos1, Vector3 screenPos2)
        {
            //Go from the bottom right to top left
            screenPos1.y = Screen.height - screenPos1.y;
            screenPos2.y = Screen.height - screenPos2.y;

            //Corners
            Vector3 bottomRight = Vector3.Max(screenPos1, screenPos2);
            Vector3 topLeft = Vector3.Min(screenPos1, screenPos2);

            //Create the rectangle
            return Rect.MinMaxRect(topLeft.x, topLeft.y, bottomRight.x, bottomRight.y);
        }

        public static Bounds GetViewportBounds(Camera cam, Vector3 screenPos1, Vector3 screenPos2)
        {
            Vector3 pos1 = cam.ScreenToViewportPoint(screenPos1);
            Vector3 pos2 = cam.ScreenToViewportPoint(screenPos2);

            Vector3 min = Vector3.Min(pos1, pos2);
            Vector3 max = Vector3.Max(pos1, pos2);

            min.z = cam.nearClipPlane;
            max.z = cam.farClipPlane;

            Bounds bounds = new Bounds();
            bounds.SetMinMax(min, max);

            return bounds;
        }
    }
}

