using UnityEngine;

// ============================================================================
//  GrassTrailEmitter —— 挂在"会踩草的东西"上（玩家 / 脚 / 载具）
//
//  只负责两件事：
//    1. 把自己的位置登记给 GrassTrailSystem
//    2. 用两帧之间的位移算出速度（拖尾的拉伸方向和长度靠它）
//
//  后面接自己的角色时，把这个组件挂到角色根节点（或左右脚各挂一个）即可。
// ============================================================================

[AddComponentMenu("草地/Grass Trail Emitter")]
public class GrassTrailEmitter : MonoBehaviour
{
    [Tooltip("这片区域内的草会被压弯（米）")]
    public float radius = 0.55f;

    [Tooltip("推力倍率：1 = 正常，2 = 一脚踩下去更狠")]
    public float strength = 1f;

    [Tooltip("是否用移动方向拉伸拖尾（关掉就是一个个圆）")]
    public bool stretchWithVelocity = true;

    /// <summary>世界空间速度（只看水平方向）。</summary>
    public Vector3 Velocity { get; private set; }

    Vector3 _lastPos;
    bool _hasLast;

    void OnEnable()
    {
        _lastPos = transform.position;
        _hasLast = true;
        GrassTrailSystem.Register(this);
    }

    void OnDisable()
    {
        GrassTrailSystem.Unregister(this);
    }

    void Update()
    {
        if (!_hasLast)
        {
            _lastPos = transform.position;
            _hasLast = true;
            return;
        }

        float dt = Time.deltaTime;
        if (dt <= 1e-5f) return;

        Vector3 delta = transform.position - _lastPos;
        delta.y = 0f;
        Velocity = delta / dt;
        _lastPos = transform.position;
    }

    void OnDrawGizmosSelected()
    {
        Gizmos.color = new Color(1f, 0.55f, 0.1f, 0.6f);
        Gizmos.DrawWireSphere(transform.position, radius);

        if (stretchWithVelocity && Application.isPlaying)
        {
            Gizmos.color = Color.yellow;
            Gizmos.DrawLine(transform.position, transform.position + Velocity);
        }
    }
}
