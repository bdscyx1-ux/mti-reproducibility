using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.SceneManagement;

public class GameManager : MonoBehaviour
{
    public void SwitchSceneToNavMesh()
    {
        SceneManager.LoadScene(1);
    }

    public void SwitchSceneToFlowField()
    {
        SceneManager.LoadScene(2);
    }

    public void SwitchSceneToMenu()
    {
        SceneManager.LoadScene(0);
    }

    public void ExitGame()
    {
        Application.Quit();
    }
}
